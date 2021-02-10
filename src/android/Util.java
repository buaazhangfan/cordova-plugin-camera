package org.apache.cordova.camera;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.hardware.Camera;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.util.List;

public class Util {

    private final String TAG = "Camera Utility";

    public static void closeSilently (Closeable c) {
        if (c == null) return;
        try {
            c.close();
        } catch (Throwable t) {
            // do nothing
        }
    }

    public static Camera.Size getOptimalPreiewSize(List<Camera.Size> sizes, int w, int h) {
        final double ASPECT_TOLERANCE = 0.1;
        double targetRatio = (double) h / w;

        if (sizes == null) {
            return null;
        }

        Camera.Size optimalSize = null;
        double minDiff = Double.MAX_VALUE;

        int targetHeight = h;

        for (Camera.Size size : sizes) {
            double ratio;
            if (size.width > size.height) {
                ratio = (double) size.width / size.height;
            } else {
                ratio = (double) size.height / size.width;
            }
            if (Math.abs(ratio - targetRatio) > ASPECT_TOLERANCE) {
                continue;
            }

            if (Math.abs(size.height - targetHeight) < minDiff) {
                optimalSize = size;
                minDiff = Math.abs(size.height - targetHeight);
            }
        }

        if (optimalSize == null) {
            minDiff = Double.MAX_VALUE;
            for (Camera.Size size : sizes) {
                if (Math.abs(size.height - targetHeight) < minDiff) {
                    optimalSize = size;
                    minDiff = Math.abs(size.height - targetHeight);
                }
            }
        }


        return optimalSize;
    }

    public static Bitmap getBitMapfromByte(byte[] data) {
        return BitmapFactory.decodeByteArray(data, 0, data.length);
    }

    public static Bitmap centerCrop(Bitmap image, double viewRatio) {
        int height = image.getHeight();
        int width = image.getWidth();
        int offset = height - (int)(width * viewRatio);
        int rectWidth = (int) (width * 3.f / 4.f);
        int rectHeight = (int) (rectWidth * 9.f / 16.f);
        int x = (width - rectWidth) / 2;
        int y = (height - offset - rectHeight) / 2;

        return Bitmap.createBitmap(image, x, y, rectWidth, rectHeight);

    }

    public static byte[] getBytefromBitMap(Bitmap image) {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        image.compress(Bitmap.CompressFormat.JPEG, 100, baos);
        byte[] b = baos.toByteArray();

        return b;
    }

}
