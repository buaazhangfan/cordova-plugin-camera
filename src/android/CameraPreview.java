package org.apache.cordova.camera;

import android.app.Activity;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RectF;
import android.hardware.Camera;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import org.apache.cordova.LOG;

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
    private Camera.CameraInfo mInfo;
    private Activity mActivity;
    private int mDisplayOrientation;

    public CameraPreview(Context context, Camera camera, int id, Activity activity) {
        super(context);
        mContext = context;
        mCamera = camera;
        mActivity = activity;

        mSupportedPreviewSizes = mCamera.getParameters().getSupportedPreviewSizes();
        mSupportedPictureSizes = mCamera.getParameters().getSupportedPictureSizes();

        mInfo = new Camera.CameraInfo();
        Camera.getCameraInfo(id, mInfo);

        int deviceOrientation = Util.getDisplayOrientation(mActivity);
        int cameraOrientation = Util.getCameraOrientation(id);
        mDisplayOrientation = Util.getCameraDisplayOrientation(deviceOrientation, cameraOrientation);


        mHolder = getHolder();
        mHolder.addCallback(this);
        mHolder.setType(SurfaceHolder.SURFACE_TYPE_PUSH_BUFFERS);
    }

    public void surfaceCreated(SurfaceHolder holder) {
        try {
            Camera.Parameters params = mCamera.getParameters();
            // force the view to be portrait
            if (this.getResources().getConfiguration().orientation != Configuration.ORIENTATION_LANDSCAPE) {
                params.set("orientation", "portrait");
                mCamera.setDisplayOrientation(mDisplayOrientation);
            } else {
                params.set("orientation", "landscape");
                mCamera.setDisplayOrientation(0);
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
            LOG.e(TAG, "Error setting camera preview: " + e.getMessage());
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
            LOG.e(TAG, "Error stop camera preview: " + e.getMessage());
        }

        try {
            mCamera.setPreviewDisplay(mHolder);
            mCamera.startPreview();
        } catch (Exception e) {
            LOG.e(TAG, "Error starting camera preview: " + e.getMessage());
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

    @Override
    protected void dispatchDraw(Canvas canvas) {
        super.dispatchDraw(canvas);
        super.dispatchDraw(canvas);
        float viewWidth = (float) getWidth();
        float viewHeight = (float) getHeight();
        float rectWidth = (viewWidth * 3.f / 4.f);
        float rectHeight = (rectWidth * 9.f / 16.f);
        float left = viewWidth / 2 - rectWidth / 2;
        float top = viewHeight / 2 - rectHeight / 2;
        int viewportCornerRadius = 8;
        Paint eraser = new Paint();
        eraser.setAntiAlias(true);
        eraser.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.CLEAR));
        RectF rect = new RectF(left, top, left + rectWidth, top + rectHeight);
        RectF frame = new RectF(left - 2.f, top - 2.f, left + rectWidth + 4.f, top + rectHeight + 4.f);
        Path path = new Path();
        Paint stroke = new Paint();
        stroke.setAntiAlias(true);
        stroke.setStrokeWidth(4);
        stroke.setColor(Color.WHITE);
        stroke.setStyle(Paint.Style.STROKE);
        path.addRoundRect(frame, (float) viewportCornerRadius, (float) viewportCornerRadius, Path.Direction.CW);
        canvas.drawPath(path, stroke);
        canvas.drawRoundRect(rect, (float) viewportCornerRadius, (float) viewportCornerRadius, eraser);
    }
}
