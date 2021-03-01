package org.apache.cordova.camera;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.hardware.Camera;
import android.view.Surface;

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

        int targetHeight = w;

        for (Camera.Size size : sizes) {
            double ratio;
            ratio = (double) size.width / size.height;

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

    public static Bitmap centerCrop(Bitmap image, int rotation) {
        int height = image.getHeight();
        int width = image.getWidth();

        int rectHeight = (int) (height * 3.f / 4.f);
        int rectWidth = (int) (rectHeight * 9.f / 16.f);
        int x = (width - rectWidth) / 2;
        int y = (height - rectHeight) / 2;
        Matrix matrix = new Matrix();
        matrix.setRotate(rotation);

        return Bitmap.createBitmap(image, x, y, rectWidth, rectHeight, matrix, true);

    }

    public static byte[] getBytefromBitMap(Bitmap image) {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        image.compress(Bitmap.CompressFormat.JPEG, 100, baos);
        byte[] b = baos.toByteArray();

        return b;
    }

    public static int getBackCameraId() {
        Camera.CameraInfo cameraInfo = new Camera.CameraInfo();
        for (int i = 0; i < Camera.getNumberOfCameras(); i++) {
            Camera.getCameraInfo(i, cameraInfo);
            if (cameraInfo.facing == Camera.CameraInfo.CAMERA_FACING_BACK) {
                return i;
            }
        }

        return -1;
    }

    public static int getDisplayOrientation(Activity activity) {
        int rotation = activity.getWindowManager().getDefaultDisplay().getRotation();
        switch (rotation) {
            case Surface.ROTATION_0: return 0;
            case Surface.ROTATION_90: return 90;
            case Surface.ROTATION_180: return 180;
            case Surface.ROTATION_270: return 270;
        }

        return 0;
    }

    public static int getCameraOrientation(int cameraId) {
        Camera.CameraInfo info = new Camera.CameraInfo();
        Camera.getCameraInfo(cameraId, info);
        return info.orientation;
    }

    public static int getCameraDisplayOrientation(int degrees, int cameraOrientation) {
        return (cameraOrientation - degrees + 360) % 360;
    }

}
