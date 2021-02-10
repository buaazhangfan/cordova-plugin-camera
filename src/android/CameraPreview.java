package org.apache.cordova.camera;

import android.content.Context;
import android.content.res.Configuration;
import android.hardware.Camera;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import java.io.IOException;
import java.util.List;

public class CameraPreview extends SurfaceView implements SurfaceHolder.Callback {
    private final String TAG = "CameraPreview";

    private Context mContext;
    private SurfaceHolder mHolder;
    private Camera mCamera;
    private List<Camera.Size> mSupportedPreviewSizes;
    private List<Camera.Size> mSupportedPictureSizes;
    private Camera.Size mPreviewSize;
    private Camera.Size mPictureSize;

    public CameraPreview(Context context, Camera camera) {
        super(context);
        mContext = context;
        mCamera = camera;

        // supported preview sizes
        mSupportedPreviewSizes = mCamera.getParameters().getSupportedPreviewSizes();
        mSupportedPictureSizes = mCamera.getParameters().getSupportedPictureSizes();

        mHolder = getHolder();
        mHolder.addCallback(this);
        mHolder.setType(SurfaceHolder.SURFACE_TYPE_PUSH_BUFFERS);
    }

    public void surfaceCreated(SurfaceHolder holder) {
        try {
            Log.e("actually height", String.valueOf(getHeight()));
            Camera.Parameters params = mCamera.getParameters();

            // force the view to be portrait
            if (this.getResources().getConfiguration().orientation != Configuration.ORIENTATION_LANDSCAPE) {
                params.set("orientation", "portrait");
                mCamera.setDisplayOrientation(90);
                params.setRotation(90);
            } else {
                params.set("orientation", "landscape");
                mCamera.setDisplayOrientation(0);
                params.setRotation(0);
            }

            if (params.getSupportedFocusModes().contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE)) {
                params.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);
            }

            params.setPreviewSize(mPreviewSize.width, mPreviewSize.height);
            params.setPictureSize(mPictureSize.width, mPictureSize.height);
            mCamera.setParameters(params);
            mCamera.setPreviewDisplay(holder);
            mCamera.startPreview();
        } catch (IOException e) {
            Log.e(TAG, "Error setting camera preview: " + e.getMessage());
        }
    }

    public void surfaceDestroyed(SurfaceHolder holder) {
    }

    public void surfaceChanged(SurfaceHolder holder, int format, int w, int h) {
        if (mHolder.getSurface() == null) {
            return;
        }

        try {
            mCamera.stopPreview();
        } catch (Exception e) {
            Log.e(TAG, "Error stop camera preview: " + e.getMessage());
        }

        try {
            mCamera.setPreviewDisplay(mHolder);
            mCamera.startPreview();
        } catch (Exception e) {
            Log.e(TAG, "Error starting camera preview: " + e.getMessage());
        }
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {

        final int width = resolveSize(getSuggestedMinimumWidth(), widthMeasureSpec);
        final int height = resolveSize(getSuggestedMinimumHeight(), heightMeasureSpec);

        if (mSupportedPreviewSizes != null) {
            mPreviewSize = Util.getOptimalPreiewSize(mSupportedPreviewSizes, width, height);
        }

        if (mSupportedPictureSizes != null) {
            mPictureSize = Util.getOptimalPreiewSize(mSupportedPictureSizes, width, height);
        }

        if (mPreviewSize != null) {
            float ratio;
            if (mPreviewSize.height >= mPreviewSize.width) {
                ratio = (float) mPreviewSize.height / (float) mPreviewSize.width;
            } else {
                ratio = (float) mPreviewSize.width / (float) mPreviewSize.height;
            }

            setMeasuredDimension(width, (int) (width * ratio));

        }
    }


}
