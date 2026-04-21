package com.cappitolian.plugins.httplocalserviceswifter;

import android.content.Context;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.text.format.Formatter;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;

import org.json.JSONObject;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

import fi.iki.elonen.NanoHTTPD;

public class HttpLocalServerSwifter {
    // Private static final properties
    private static final String TAG = "HttpLocalServerSwifter";
    private static final int DEFAULT_PORT = 8080;
    private static final int DEFAULT_TIMEOUT_SECONDS = 5;
    private static final String FALLBACK_IP = "127.0.0.1";
    // Changed to String to transport the full JSON response from JS
    private static final ConcurrentHashMap<String, CompletableFuture<String>> pendingResponses = new ConcurrentHashMap<>();
    // Add inside LocalNanoServer
    private static final ConcurrentHashMap<String, long[]> rateLimitMap = new ConcurrentHashMap<>();
    private static final int RATE_LIMIT = 30; // requests
    private static final long RATE_WINDOW_MS = 60_000; // per minute

    // Private final properties
    private final Plugin plugin;
    private final int port;
    private final int timeoutSeconds;

    // Private properties
    private LocalNanoServer server;

    private static boolean isRateLimited(String ip) {
        long now = System.currentTimeMillis();

        rateLimitMap.compute(ip, (key, timestamps) -> {
            if (timestamps == null)
                timestamps = new long[] { now, 1 };
            else if (now - timestamps[0] > RATE_WINDOW_MS) {
                timestamps[0] = now;
                timestamps[1] = 1;
            } else
                timestamps[1]++;

            return timestamps;
        });

        long[] entry = rateLimitMap.get(ip);

        return entry != null && entry[1] > RATE_LIMIT;
    }

    public HttpLocalServerSwifter(@NonNull Plugin plugin) {
        this(plugin, DEFAULT_PORT, DEFAULT_TIMEOUT_SECONDS);
    }

    public HttpLocalServerSwifter(@NonNull Plugin plugin, int port, int timeoutSeconds) {
        this.plugin = plugin;
        this.port = port;
        this.timeoutSeconds = timeoutSeconds;
    }

    public void connect(@NonNull PluginCall call) {
        if (server != null && server.isAlive()) {
            call.reject("Server is already running");

            return;
        }

        try {
            String localIp = getLocalIpAddress(plugin.getContext());

            server = new LocalNanoServer(localIp, port, plugin, timeoutSeconds);
            server.start();

            JSObject response = new JSObject();

            response.put("ip", localIp);
            response.put("port", port);

            call.resolve(response);

            Log.i(TAG, "Server started at " + localIp + ":" + port);
        } catch (IOException e) {
            Log.e(TAG, "Failed to start server", e);

            call.reject("Failed to start server: " + e.getMessage());
        }
    }

    public void disconnect(@Nullable PluginCall call) {
        if (server != null) {
            server.stop();

            server = null;

            pendingResponses.clear();

            Log.i(TAG, "Server stopped");
        }
        if (call != null)
            call.resolve();
    }

    /**
     * Completes the future with the full JS response object (body, status, headers)
     */
    public static void handleJsResponse(@NonNull String requestId, @NonNull JSObject responseData) {
        CompletableFuture<String> future = pendingResponses.remove(requestId);

        if (future != null && !future.isDone()) {
            future.complete(responseData.toString());
            Log.d(TAG, "Response object delivered to future for ID: " + requestId);
        }
    }

    private @NonNull String getLocalIpAddress(@NonNull Context context) {
        try {
            WifiManager wifiManager = (WifiManager) context.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);

            if (wifiManager == null)
                return FALLBACK_IP;

            WifiInfo wifiInfo = wifiManager.getConnectionInfo();

            if (wifiInfo == null)
                return FALLBACK_IP;

            int ipAddress = wifiInfo.getIpAddress();

            return ipAddress == 0 ? FALLBACK_IP : Formatter.formatIpAddress(ipAddress);
        } catch (Exception e) {
            return FALLBACK_IP;
        }
    }

    private static class LocalNanoServer extends NanoHTTPD {
        private final Plugin plugin;
        private final int timeoutSeconds;

        public LocalNanoServer(@NonNull String hostname, int port, @NonNull Plugin plugin, int timeoutSeconds) {
            super(hostname, port);
            this.plugin = plugin;
            this.timeoutSeconds = timeoutSeconds;
        }

        @Override
        public Response serve(@NonNull IHTTPSession session) {
            if (Method.OPTIONS.equals(session.getMethod())) {
                return createCorsResponse();
            }

            // Rate limiting
            String clientIp = session.getHeaders().getOrDefault("http-client-ip",
                    session.getHeaders().getOrDefault("remote-addr", "unknown"));

            if (isRateLimited(clientIp)) {
                Response r = newFixedLengthResponse(
                        Response.Status.lookup(429), "application/json",
                        "{\"success\":false,\"error\":\"Too many requests\"}");

                addCorsHeaders(r);

                return r;
            }

            // Native CORS Preflight handling for efficiency
            if (Method.OPTIONS.equals(session.getMethod())) {
                return createCorsResponse();
            }

            try {
                String method = session.getMethod().name();
                String path = session.getUri();
                String body = extractBody(session);

                Map<String, String> headers = session.getHeaders();
                Map<String, String> params = session.getParms();

                // Wait for TypeScript to process logic and provide the complex response
                String jsResponseRaw = processRequest(method, path, body, headers, params);
                return createDynamicResponse(jsResponseRaw);
            } catch (Exception e) {
                return createErrorResponse("Internal server error: " + e.getMessage(), Response.Status.INTERNAL_ERROR);
            }
        }

        /**
         * Parses the JSON from JS and builds a NanoHTTPD Response with custom status
         * and headers
         */
        private Response createDynamicResponse(String jsResponseRaw) {
            try {
                JSONObject res = new JSONObject(jsResponseRaw);
                String body = res.optString("body", "");

                int statusCode = res.optInt("status", 200);

                JSONObject customHeaders = res.optJSONObject("headers");

                Response.IStatus status = Response.Status.lookup(statusCode);
                Response response = newFixedLengthResponse(status != null ? status : Response.Status.OK,
                        "application/json", body);

                // Add standard CORS headers
                addCorsHeaders(response);

                // Inject custom headers from TypeScript (allows overriding CORS or
                // Content-Type)
                if (customHeaders != null) {
                    java.util.Iterator<String> keys = customHeaders.keys();

                    while (keys.hasNext()) {
                        String key = keys.next();
                        response.addHeader(key, customHeaders.getString(key));
                    }
                }
                return response;
            } catch (Exception e) {
                // Fallback for simple string responses or parsing errors
                return newFixedLengthResponse(Response.Status.OK, "application/json", jsResponseRaw);
            }
        }

        private String extractBody(@NonNull IHTTPSession session) {
            Method method = session.getMethod();

            if (method != Method.POST && method != Method.PUT && method != Method.PATCH)
                return null;

            try {
                HashMap<String, String> files = new HashMap<>();
                session.parseBody(files);
                String body = files.get("postData");

                return (body == null || body.isEmpty()) ? session.getQueryParameterString() : body;
            } catch (IOException | ResponseException e) {
                return null;
            }
        }

        private String processRequest(String method, String path, String body, Map<String, String> headers,
                Map<String, String> params) {
            String requestId = UUID.randomUUID().toString();
            JSObject requestData = new JSObject();
            requestData.put("requestId", requestId);
            requestData.put("method", method);
            requestData.put("path", path);

            if (body != null)
                requestData.put("body", body);

            // Add headers
            JSObject headersObj = new JSObject();

            for (Map.Entry<String, String> entry : headers.entrySet()) {
                headersObj.put(entry.getKey(), entry.getValue());
            }

            requestData.put("headers", headersObj);

            CompletableFuture<String> future = new CompletableFuture<>();
            pendingResponses.put(requestId, future);

            if (plugin instanceof HttpLocalServerSwifterPlugin) {
                ((HttpLocalServerSwifterPlugin) plugin).fireOnRequest(requestData);
            }

            try {
                return future.get(timeoutSeconds, TimeUnit.SECONDS);
            } catch (Exception e) {
                return "{\"error\":\"Timeout or processing error\"}";
            } finally {
                pendingResponses.remove(requestId);
            }
        }

        private Response createCorsResponse() {
            Response response = newFixedLengthResponse(Response.Status.NO_CONTENT, "text/plain", "");

            addCorsHeaders(response);

            return response;
        }

        private void addCorsHeaders(@NonNull Response response) {
            response.addHeader("Access-Control-Allow-Origin", "*");
            response.addHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
            response.addHeader("Access-Control-Allow-Headers",
                    "Origin, Content-Type, Accept, Authorization, X-Requested-With, x-api-key");
            response.addHeader("Access-Control-Max-Age", "3600");
            // Prevents TCP connection reuse. NanoHTTPD does not handle keep-alive
            // correctly under rapid sequential requests, causing ERR_INVALID_HTTP_RESPONSE.
            response.addHeader("Connection", "close");
        }

        private Response createErrorResponse(String message, Response.Status status) {
            return newFixedLengthResponse(status, "application/json", "{\"error\":\"" + message + "\"}");
        }
    }
}