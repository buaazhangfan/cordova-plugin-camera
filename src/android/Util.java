package org.apache.cordova.camera;

import java.io.Closeable;

public class Util {

    public static void closeSilently (Closeable c) {
        if (c == null) return;
        try {
            c.close();
        } catch (Throwable t) {
            // do nothing
        }
    }
}
