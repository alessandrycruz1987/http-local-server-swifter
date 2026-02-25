package com.cappitolian.plugins.httplocalserviceswifter;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "HttpLocalServerSwifter")
public class HttpLocalServerSwifterPlugin extends Plugin {
    private HttpLocalServerSwifter localServer;

    @Override
    public void load() {
        super.load();
        localServer = new HttpLocalServerSwifter(this);
    }

    @PluginMethod
    public void connect(PluginCall call) {
        localServer.connect(call);
    }

    @PluginMethod
    public void disconnect(PluginCall call) {
        localServer.disconnect(call);
    }

    @PluginMethod
    public void sendResponse(PluginCall call) {
        String requestId = call.getString("requestId");
        if (requestId == null || requestId.isEmpty()) {
            call.reject("Missing requestId");
            return;
        }
        
        // Pass the entire PluginCall data object to handleJsResponse
        // This allows us to capture 'status' and 'headers' along with the 'body'
        HttpLocalServerSwifter.handleJsResponse(requestId, call.getData());
        call.resolve();
    }

    public void fireOnRequest(JSObject data) {
        notifyListeners("onRequest", data);
    }
}