package ir.donitoo.cheeno;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.util.Base64;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.HashSet;
import java.util.Set;

/**
 * Opens the Android system picker (ACTION_GET_CONTENT, no storage permission needed)
 * and emits the chosen image as base64 through "photo_picked".
 */
public class CheenoPicker extends GodotPlugin {
    private static final int REQ = 7301;

    public CheenoPicker(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "CheenoPicker";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> s = new HashSet<>();
        s.add(new SignalInfo("photo_picked", String.class));
        s.add(new SignalInfo("photo_failed", String.class));
        return s;
    }

    private AudioRecord rec;
    private final Object recLock = new Object();

    private String recInfo = "none";

    @UsedByGodot
    public String recInfo() { return recInfo; }

    @UsedByGodot
    public boolean recStart() {
        synchronized (recLock) {
            if (rec != null) return true;
            int[] srcs = new int[]{MediaRecorder.AudioSource.MIC, MediaRecorder.AudioSource.VOICE_COMMUNICATION, MediaRecorder.AudioSource.DEFAULT};
            for (int src : srcs) {
                try {
                    int min = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
                    if (min <= 0) { recInfo = "minbuf" + min; continue; }
                    AudioRecord r = new AudioRecord(src, 16000,
                            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, min * 4);
                    if (r.getState() != AudioRecord.STATE_INITIALIZED) {
                        r.release();
                        recInfo = "init-fail" + src;
                        continue;
                    }
                    r.startRecording();
                    if (r.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING) {
                        r.release();
                        recInfo = "nostart" + src;
                        continue;
                    }
                    rec = r;
                    recInfo = "ok" + src;
                    return true;
                } catch (Throwable t) {
                    recInfo = "err:" + t.getClass().getSimpleName();
                }
            }
            return false;
        }
    }

    @UsedByGodot
    public String recRead() {
        try {
        synchronized (recLock) {
            if (rec == null) return "";
            byte[] b = new byte[6400];
            int n = rec.read(b, 0, b.length, AudioRecord.READ_NON_BLOCKING);
            if (n <= 0) return "";
            return Base64.encodeToString(b, 0, n, Base64.NO_WRAP);
        }
        } catch (Throwable t) {
            return "";
        }
    }

    @UsedByGodot
    public void recStop() {
        synchronized (recLock) {
            if (rec == null) return;
            try { rec.stop(); } catch (Throwable t) {}
            try { rec.release(); } catch (Throwable t) {}
            rec = null;
        }
    }

    @Override
    public void onMainDestroy() {
        recStop();
    }

    @UsedByGodot
    public void pick() {
        final Activity a = getActivity();
        if (a == null) {
            emitSignal("photo_failed", "no activity");
            return;
        }
        final Intent i = new Intent(Intent.ACTION_GET_CONTENT);
        i.setType("image/*");
        i.addCategory(Intent.CATEGORY_OPENABLE);
        a.runOnUiThread(() -> {
            try {
                a.startActivityForResult(Intent.createChooser(i, "انتخاب عکس"), REQ);
            } catch (Exception e) {
                emitSignal("photo_failed", String.valueOf(e.getMessage()));
            }
        });
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQ) {
            return;
        }
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            emitSignal("photo_failed", "cancel");
            return;
        }
        Uri uri = data.getData();
        try {
            Activity a = getActivity();
            InputStream in = a.getContentResolver().openInputStream(uri);
            if (in == null) {
                emitSignal("photo_failed", "open failed");
                return;
            }
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) {
                bo.write(buf, 0, n);
                if (bo.size() > 25 * 1024 * 1024) {
                    in.close();
                    emitSignal("photo_failed", "too large");
                    return;
                }
            }
            in.close();
            emitSignal("photo_picked", Base64.encodeToString(bo.toByteArray(), Base64.NO_WRAP));
        } catch (Exception e) {
            emitSignal("photo_failed", String.valueOf(e.getMessage()));
        }
    }
}
