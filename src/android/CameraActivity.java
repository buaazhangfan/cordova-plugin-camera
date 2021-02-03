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

    Camera camera;
    FrameLayout frameLayout;
    CameraPreview mPreview;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mContentResolver = getContentResolver();
        setContentView(R.layout.activity_camera);
        frameLayout = (FrameLayout) findViewById(R.id.camera_preview);

        camera = Camera.open();

        mPreview = new CameraPreview(this, camera);

        frameLayout.addView(mPreview);


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

        if (camera == null) {
            camera = Camera.open();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        releaseCamera();
    }

    public void captureImage(View v) {
        if (camera != null) {
            camera.takePicture(null, null, mPictureCallback);
        }
    }

    private void releaseCamera() {
        if (camera != null) {
            camera.stopPreview();
            camera.setPreviewCallback(null);
            camera.release();
            camera = null;
        }
    }


}
