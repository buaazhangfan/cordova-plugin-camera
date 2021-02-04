package org.apache.cordova.camera;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Intent;
import android.hardware.Camera;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.view.View;
import android.widget.FrameLayout;

import com.oraclecorp.internal.cxm.salescloud.R;

import org.apache.cordova.LOG;

import java.io.IOException;
import java.io.OutputStream;


public class CameraActivity extends Activity {

    private final String TAG = "CameraActivity";
    private ContentResolver mContentResolver;
    private Uri mSaveUri;

    private Camera mCamera;
    private FrameLayout mFrameLayout;
    private CameraPreview mPreview;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mContentResolver = getContentResolver();
        setContentView(R.layout.activity_camera);
        mFrameLayout = (FrameLayout) findViewById(R.id.camera_preview);

        mCamera = Camera.open();

        mPreview = new CameraPreview(this, mCamera);

        mFrameLayout.addView(mPreview);


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
                    outputStream = mContentResolver.openOutputStream(mSaveUri);
                    outputStream.write(data);
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


}
