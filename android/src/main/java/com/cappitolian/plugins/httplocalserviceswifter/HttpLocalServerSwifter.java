package com.cappitolian.plugins.httplocalserviceswifter;

import com.getcapacitor.Logger;

public class HttpLocalServerSwifter {

    public String echo(String value) {
        Logger.info("Echo", value);
        return value;
    }
}
