package org.apache.cordova.camera;

import android.hardware.Camera;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.widget.FrameLayout;

import com.oraclecorp.internal.cxm.salescloud.R;


public class CameraActivity extends AppCompatActivity {

    Camera camera;
    FrameLayout frameLayout;
    CameraPreview mPreview;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_camera);
        frameLayout = (FrameLayout) findViewById(R.id.camera_preview);

        camera = Camera.open();

        mPreview = new CameraPreview(this, camera);


    }
}