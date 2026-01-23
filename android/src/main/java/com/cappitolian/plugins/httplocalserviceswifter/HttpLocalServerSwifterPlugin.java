package com.cappitolian.plugins.httplocalserviceswifter;

import android.util.Log;

import androidx.annotation.NonNull;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "HttpLocalServerSwifter")
public class HttpLocalServerSwifterPlugin extends Plugin {
    private static final String TAG = "HttpLocalServerSwifterPlugin";
    private HttpLocalServerSwifter localServer;
    @Override
    public void load() {
        super.load();
        // Inicializar el servidor con configuración por defecto
        localServer = new HttpLocalServerSwifter(this);
        
        // O con configuración personalizada:
        // localServer = new HttpLocalServerSwifter(this, 8080, 5); // puerto y timeout
        
        Log.d(TAG, "Plugin loaded");
    }

    @PluginMethod
    public void connect(PluginCall call) {
        if (localServer == null) {
            localServer = new HttpLocalServerSwifter(this);
        }
        localServer.connect(call);
    }

    @PluginMethod
    public void disconnect(PluginCall call) {
        if (localServer != null) {
            localServer.disconnect(call);
        } else {
            call.resolve();
        }
    }

    @PluginMethod
    public void sendResponse(PluginCall call) {
        String requestId = call.getString("requestId");
        String body = call.getString("body");
        
        if (requestId == null || requestId.isEmpty()) {
            call.reject("Missing requestId");
            return;
        }
        
        if (body == null || body.isEmpty()) {
            call.reject("Missing body");
            return;
        }
        
        HttpLocalServerSwifter.handleJsResponse(requestId, body);
        call.resolve();
    }

    /**
    * Called by HttpLocalServerSwifter to notify JavaScript of incoming requests
    */
    public void fireOnRequest(@NonNull JSObject data) {
        notifyListeners("onRequest", data);
    }
    
    @Override
    protected void handleOnDestroy() {
        if (localServer != null) {
            localServer.disconnect(null);
            localServer = null;
        }
        super.handleOnDestroy();
    }
}