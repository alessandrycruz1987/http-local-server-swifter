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

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import fi.iki.elonen.NanoHTTPD;

/**
* Local HTTP server implementation for Android using NanoHTTPD.
* Handles incoming HTTP requests and communicates with JavaScript layer.
*/
public class HttpLocalServerSwifter {
    // MARK: - Constants
    private static final String TAG = "HttpLocalServerSwifter";
    private static final int DEFAULT_PORT = 8080;
    private static final int DEFAULT_TIMEOUT_SECONDS = 5;
    private static final String FALLBACK_IP = "127.0.0.1";
    
    // MARK: - Properties
    private LocalNanoServer server;
    private final Plugin plugin;
    private final int port;
    private final int timeoutSeconds;
    
    private static final ConcurrentHashMap<String, CompletableFuture<String>> pendingResponses = new ConcurrentHashMap<>();
    
    // MARK: - Constructor
    public HttpLocalServerSwifter(@NonNull Plugin plugin) {
        this(plugin, DEFAULT_PORT, DEFAULT_TIMEOUT_SECONDS);
    }
    
    public HttpLocalServerSwifter(@NonNull Plugin plugin, int port, int timeoutSeconds) {
        this.plugin = plugin;
        this.port = port;
        this.timeoutSeconds = timeoutSeconds;
    }
    
    // MARK: - Public Methods
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
            
            // Clear all pending responses
            pendingResponses.clear();
            
            Log.i(TAG, "Server stopped");
        }
        
        if (call != null) {
            call.resolve();
        }
    }
    
    // MARK: - Static Methods
    /**
    * Called by plugin when JavaScript responds to a request
    */
    public static void handleJsResponse(@NonNull String requestId, @NonNull String body) {
        CompletableFuture<String> future = pendingResponses.remove(requestId);
        if (future != null && !future.isDone()) {
            future.complete(body);
            Log.d(TAG, "Response received for request: " + requestId);
        } else {
            Log.w(TAG, "No pending request found for ID: " + requestId);
        }
    }
    
    // MARK: - Private Methods
    /**
    * Get the local WiFi IP address
    */
    @NonNull
    private String getLocalIpAddress(@NonNull Context context) {
        try {
            WifiManager wifiManager = (WifiManager) context.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            
            if (wifiManager == null) {
                Log.w(TAG, "WifiManager is null, using fallback IP");
                return FALLBACK_IP;
            }
            
            WifiInfo wifiInfo = wifiManager.getConnectionInfo();
            if (wifiInfo == null) {
                Log.w(TAG, "WifiInfo is null, using fallback IP");
                return FALLBACK_IP;
            }
            
            int ipAddress = wifiInfo.getIpAddress();
            if (ipAddress == 0) {
                Log.w(TAG, "IP address is 0, using fallback IP");
                return FALLBACK_IP;
            }
            
            return Formatter.formatIpAddress(ipAddress);
        } catch (Exception e) {
            Log.e(TAG, "Error getting IP address", e);
            return FALLBACK_IP;
        }
    }
    
    // MARK: - Inner Class: LocalNanoServer
    /**
    * NanoHTTPD server implementation that handles HTTP requests
    */
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
            String method = session.getMethod().name();
            String path = session.getUri();
            
            // Handle CORS preflight
            if (Method.OPTIONS.equals(session.getMethod())) {
                return createCorsResponse();
            }
            
            try {
                // Extract request data
                String body = extractBody(session);
                Map<String, String> headers = session.getHeaders();
                Map<String, String> params = session.getParms();
                
                // Process request
                String responseBody = processRequest(method, path, body, headers, params);
                
                return createJsonResponse(responseBody, Response.Status.OK);
            } catch (Exception e) {
                Log.e(TAG, "Error processing request", e);
                return createErrorResponse("Internal server error: " + e.getMessage(), 
                        Response.Status.INTERNAL_ERROR);
            }
        }
        
        /**
        * Extract body from POST/PUT/PATCH requests
        */
        @Nullable
        private String extractBody(@NonNull IHTTPSession session) {
            Method method = session.getMethod();
            
            if (method != Method.POST && method != Method.PUT && method != Method.PATCH) {
                return null;
            }
            
            try {
                HashMap<String, String> files = new HashMap<>();
                session.parseBody(files);
                
                // Body comes in the map with key "postData"
                String body = files.get("postData");
                
                // Fallback to query parameters for form-data
                if (body == null || body.isEmpty()) {
                    body = session.getQueryParameterString();
                }
                
                Log.d(TAG, "Body received (" + body.length() + " bytes): " + 
                        (body != null ? body.substring(0, Math.min(body.length(), 100)) : "null"));
                
                return body;
            } catch (IOException | ResponseException e) {
                Log.e(TAG, "Error parsing body", e);
                return null;
            }
        }
        
        /**
        * Process the request and wait for JavaScript response
        */
        @NonNull
        private String processRequest(@NonNull String method, @NonNull String path, 
                                      @Nullable String body, @NonNull Map<String, String> headers,
                                      @NonNull Map<String, String> params) {
            
            String requestId = UUID.randomUUID().toString();
            
            // Build request data for JavaScript
            JSObject requestData = new JSObject();
            requestData.put("requestId", requestId);
            requestData.put("method", method);
            requestData.put("path", path);
            
            if (body != null && !body.isEmpty()) {
                requestData.put("body", body);
            }
            
            if (!headers.isEmpty()) {
                requestData.put("headers", mapToJson(headers));
            }
            
            if (!params.isEmpty()) {
                requestData.put("query", mapToJson(params));
            }
            
            // Create future for response
            CompletableFuture<String> future = new CompletableFuture<>();
            pendingResponses.put(requestId, future);
            
            // Notify plugin
            if (plugin instanceof HttpLocalServerSwifterPlugin) {
                ((HttpLocalServerSwifterPlugin) plugin).fireOnRequest(requestData);
            } else {
                Log.e(TAG, "Plugin is not instance of HttpLocalServerSwifterPlugin");
            }
            
            // Wait for JavaScript response
            try {
                String response = future.get(timeoutSeconds, TimeUnit.SECONDS);
                Log.d(TAG, "Response received for request: " + requestId);
                return response;
            } catch (TimeoutException e) {
                Log.w(TAG, "Timeout waiting for response: " + requestId);
                return createTimeoutError(requestId);
            } catch (Exception e) {
                Log.e(TAG, "Error waiting for response: " + requestId, e);
                return createGenericError("Error waiting for response");
            } finally {
                pendingResponses.remove(requestId);
            }
        }
        
        /**
        * Convert Map to JSObject
        */
        @NonNull
        private JSObject mapToJson(@NonNull Map<String, String> map) {
            JSObject json = new JSObject();
            for (Map.Entry<String, String> entry : map.entrySet()) {
                json.put(entry.getKey(), entry.getValue());
            }
            return json;
        }
        
        /**
        * Create JSON response with CORS headers
        */
        @NonNull
        private Response createJsonResponse(@NonNull String body, @NonNull Response.Status status) {
            Response response = newFixedLengthResponse(status, "application/json", body);
            addCorsHeaders(response);
            return response;
        }
        
        /**
        * Create CORS preflight response
        */
        @NonNull
        private Response createCorsResponse() {
            Response response = newFixedLengthResponse(Response.Status.NO_CONTENT, 
                    "text/plain", "");
            addCorsHeaders(response);
            return response;
        }
        
        /**
        * Create error response
        */
        @NonNull
        private Response createErrorResponse(@NonNull String message, @NonNull Response.Status status) {
            try {
                JSONObject error = new JSONObject();
                error.put("error", message);
                return createJsonResponse(error.toString(), status);
            } catch (JSONException e) {
                return newFixedLengthResponse(status, "text/plain", message);
            }
        }
        
        /**
        * Create timeout error JSON
        */
        @NonNull
        private String createTimeoutError(@NonNull String requestId) {
            try {
                JSONObject error = new JSONObject();
                error.put("error", "Request timeout");
                error.put("requestId", requestId);
                return error.toString();
            } catch (JSONException e) {
                return "{\"error\":\"Request timeout\"}";
            }
        }
        
        /**
        * Create generic error JSON
        */
        @NonNull
        private String createGenericError(@NonNull String message) {
            try {
                JSONObject error = new JSONObject();
                error.put("error", message);
                return error.toString();
            } catch (JSONException e) {
                return "{\"error\":\"" + message + "\"}";
            }
        }
        
        /**
        * Add CORS headers to response
        */
        private void addCorsHeaders(@NonNull Response response) {
            response.addHeader("Access-Control-Allow-Origin", "*");
            response.addHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
            response.addHeader("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization");
            response.addHeader("Access-Control-Allow-Credentials", "true");
            response.addHeader("Access-Control-Max-Age", "3600");
        }
    }
}