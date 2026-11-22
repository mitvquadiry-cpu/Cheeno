package ir.donitoo.cheeno;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.util.Base64;

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

    private android.media.AudioRecord rec;

    @UsedByGodot
    public boolean recStart() {
        try {
            recStop();
            int min = android.media.AudioRecord.getMinBufferSize(16000,
                android.media.AudioFormat.CHANNEL_IN_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT);
            rec = new android.media.AudioRecord(android.media.MediaRecorder.AudioSource.VOICE_COMMUNICATION, 16000,
                android.media.AudioFormat.CHANNEL_IN_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT, Math.max(min, 16000));
            if (rec.getState() != android.media.AudioRecord.STATE_INITIALIZED) {
                rec.release();
                rec = null;
                return false;
            }
            rec.startRecording();
            return true;
        } catch (Exception e) {
            rec = null;
            return false;
        }
    }

    @UsedByGodot
    public byte[] recRead() {
        try {
            if (rec == null) return new byte[0];
            byte[] b = new byte[3200];
            int n = rec.read(b, 0, b.length, android.media.AudioRecord.READ_NON_BLOCKING);
            if (n <= 0) return new byte[0];
            byte[] r = new byte[n];
            System.arraycopy(b, 0, r, 0, n);
            return r;
        } catch (Exception e) {
            return new byte[0];
        }
    }

    @UsedByGodot
    public void recStop() {
        try {
            if (rec != null) {
                rec.stop();
                rec.release();
            }
        } catch (Exception e) {
        }
        rec = null;
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
