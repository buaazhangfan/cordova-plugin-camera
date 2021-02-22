package org.apache.cordova.camera;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.hardware.Camera;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.util.Log;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.TextView;

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
    private TextView mText;
    private ImageButton mFlashButton;

    private final String[] flashModes = {Camera.Parameters.FLASH_MODE_ON, Camera.Parameters.FLASH_MODE_OFF};
    private int fmi = 1; // flash mode index


    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mContentResolver = getContentResolver();
        setContentView(R.layout.activity_camera);

        mFrameLayout = findViewById(R.id.camera_preview);
        mText = findViewById(R.id.textOverlay);
        mFlashButton = findViewById(R.id.btn_flash);

        int width = Resources.getSystem().getDisplayMetrics().widthPixels;
        int height = Resources.getSystem().getDisplayMetrics().heightPixels;
        int transitionY = getTextPosition(width, height);
        mText.setText("Place the card inside the rectangular area");
        mText.setTranslationY(transitionY);
        mText.bringToFront();

        mCamera = Camera.open();

        Camera.Parameters params = mCamera.getParameters();

        mPreview = new CameraPreview(this, mCamera);
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

        if (fmi == 1) {
            // flash off
            fmi = 0;
            mFlashButton.setImageResource(R.drawable.ic_flash_on_holo_light);
        } else {
            fmi = 1;
            mFlashButton.setImageResource(R.drawable.ic_flash_off_holo_light);
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
                    double frameLayoutRatio = (double)mFrameLayout.getHeight() / (double)mFrameLayout.getWidth();
                    Bitmap bitmap = Util.getBitMapfromByte(data);
                    Bitmap cropmap = Util.centerCrop(bitmap, frameLayoutRatio);
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

}
