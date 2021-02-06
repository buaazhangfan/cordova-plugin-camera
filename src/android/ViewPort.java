package org.apache.cordova.camera;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RectF;
import android.hardware.Camera;
import android.util.AttributeSet;
import android.view.ViewGroup;

public class ViewPort extends ViewGroup {

    private Camera.Size mPreviewSize;

    public float rectTop;
    public float rectLeft;


    public ViewPort(Context context) {
        super(context);
    }

    public ViewPort(Context context, AttributeSet attrs) {
        this(context, attrs, 0);
    }

    public ViewPort(Context context, AttributeSet attrs, int defStyle) {
        super(context, attrs, defStyle);
    }

    @Override
    public void onLayout(boolean changed, int left, int top, int right, int bottom) {
    }

    @Override
    public boolean shouldDelayChildPressedState() {
        return false;
    }

    @Override
    protected void dispatchDraw(Canvas canvas) {
        super.dispatchDraw(canvas);
        float viewWidth = (float) getWidth();
        float viewHeight = (float) getHeight();
        float rectWidth = (viewWidth * 3.f / 4.f);
        float rectHeight = (rectWidth * 9.f / 16.f);
        float left = viewWidth / 2 - rectWidth / 2;
        float top = viewHeight / 2 - rectHeight / 2;
        this.rectLeft = left;
        this.rectTop = top;
        int viewportMargin = 32;
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
