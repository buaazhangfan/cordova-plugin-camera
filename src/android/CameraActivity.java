package org.apache.cordova.camera;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.hardware.Camera;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.TextView;

import java.io.IOException;
import java.io.OutputStream;

public class CameraActivity extends Activity {

    private final String TAG = "CameraActivity";
    private ContentResolver mContentResolver;
    private Uri mSaveUri;

    private Camera mCamera;
    private FrameLayout mFrameLayout;
    private CameraPreview mPreview;
    private TextView mText;
    private ImageButton mFlashButton;
    private int mCameraId;

    private String appResourcePackage;

    private final String[] flashModes = {Camera.Parameters.FLASH_MODE_ON, Camera.Parameters.FLASH_MODE_OFF};
    private int fmi = 1; // flash mode index

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mContentResolver = getContentResolver();

        appResourcePackage = this.getPackageName();

        setContentView(getResources().getIdentifier("activity_camera", "layout", appResourcePackage));

        int cameraPreviewId = getResources().getIdentifier("camera_preview", "id", appResourcePackage);
        int textOverlayId = getResources().getIdentifier("textOverlay", "id", appResourcePackage);
        int buttonFlashId = getResources().getIdentifier("btn_flash", "id", appResourcePackage);

        mFrameLayout = findViewById(cameraPreviewId);
        mText = findViewById(textOverlayId);
        mFlashButton = findViewById(buttonFlashId);

        int width = Resources.getSystem().getDisplayMetrics().widthPixels;
        int height = Resources.getSystem().getDisplayMetrics().heightPixels;
        mText.setText("Place the card inside the rectangular area");
        mText.setTranslationY(100);
        mText.bringToFront();

        int backCameraID = Util.getBackCameraId();
        mCameraId = backCameraID;

        mCamera = Camera.open(backCameraID);

        mPreview = new CameraPreview(this, mCamera, backCameraID, this);
        mPreview.setBackgroundColor(Color.parseColor("#7f000000"));
        mFrameLayout.addView(mPreview);

        mFlashButton.setOnClickListener(
                new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        setFlashMode();
                    }
                }
        );

    }

    private int getTextPosition(int width, int height) {
        float rectWidth = width * 3.f / 4.f;
        float rectHeight = rectWidth * 9.f / 16.f;
        float margin = (height - rectHeight) / 2.f;

        return (int)(margin - 60);
    }

    private void setFlashMode() {
        Camera.Parameters params = mCamera.getParameters();
        int flashOnId = getResources().getIdentifier("flash_on", "drawable", appResourcePackage);
        int flashOffId = getResources().getIdentifier("flash_off", "drawable", appResourcePackage);
        if (fmi == 1) {
            // flash off
            fmi = 0;
            mFlashButton.setImageResource(flashOnId);
        } else {
            fmi = 1;
            mFlashButton.setImageResource(flashOffId);
        }

        params.setFlashMode(flashModes[fmi]);
        mCamera.setParameters(params);
    }

    Camera.PictureCallback mPictureCallback = new Camera.PictureCallback() {
        @Override
        public void onPictureTaken(byte[] data, Camera camera) {
            Bundle myExtras = getIntent().getExtras();
            if (myExtras != null) {
                mSaveUri = (Uri) myExtras.getParcelable(MediaStore.EXTRA_OUTPUT);
            }
            if (mSaveUri != null) {
                OutputStream outputStream = null;
                try {
                    int rotation = getPictureRotation(mCameraId);
                    Bitmap bitmap = Util.getBitMapfromByte(data);
                    Bitmap cropmap = Util.centerCrop(bitmap, rotation);
                    byte[] cropdata = Util.getBytefromBitMap(cropmap);
                    outputStream = mContentResolver.openOutputStream(mSaveUri);
                    outputStream.write(cropdata);
                    outputStream.close();

                    setResult(RESULT_OK);
                    finish();
                } catch (IOException e) {
                    // ignore exception
                } finally {
                    Util.closeSilently(outputStream);
                }
            }
        }
    };

    @Override
    protected void onResume() {
        super.onResume();

        if (mCamera == null) {
            mCamera = Camera.open();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        releaseCamera();
    }

    public void captureImage(View v) {
        if (mCamera != null) {
            mCamera.autoFocus(new Camera.AutoFocusCallback() {
                @Override
                public void onAutoFocus(boolean success, Camera camera) {
                    if (success) {
                        mCamera.takePicture(null, null, mPictureCallback);
                    }
                }
            });
        }
    }

    private void releaseCamera() {
        if (mCamera != null) {
            mCamera.stopPreview();
            mCamera.setPreviewCallback(null);
            mCamera.release();
            mCamera = null;
        }
    }

    private int getPictureRotation(int cameraId) {
        int deviceOrientation = Util.getDisplayOrientation(this);
        int cameraOrientation = Util.getCameraOrientation(cameraId);
        return Util.getCameraDisplayOrientation(deviceOrientation, cameraOrientation);
    }

}
