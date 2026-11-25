package ir.donitoo.cheeno;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.util.Base64;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.AudioAttributes;
import android.content.Context;
import android.os.PowerManager;
import android.media.audiofx.AcousticEchoCanceler;

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

    private int oldMode = -1;

    private void route(boolean call) {
        try {
            Activity a = getActivity();
            if (a == null) return;
            AudioManager am = (AudioManager) a.getSystemService(Context.AUDIO_SERVICE);
            if (am == null) return;
            if (call) {
                if (oldMode == -1) oldMode = am.getMode();
                am.setMode(AudioManager.MODE_IN_COMMUNICATION);
                am.setSpeakerphoneOn(false);
            } else if (oldMode != -1) {
                am.setSpeakerphoneOn(false);
                am.setMode(oldMode);
                oldMode = -1;
            }
        } catch (Throwable t) {}
    }

    private PowerManager.WakeLock prox;
    private AcousticEchoCanceler aec;

    private void extras(boolean on, AudioRecord r) {
        try {
            if (on) {
                try {
                    if (aec == null && r != null && AcousticEchoCanceler.isAvailable()) {
                        aec = AcousticEchoCanceler.create(r.getAudioSessionId());
                        if (aec != null) aec.setEnabled(true);
                    }
                } catch (Throwable t) {}
                Activity a = getActivity();
                if (a == null || prox != null) return;
                PowerManager pm = (PowerManager) a.getSystemService(Context.POWER_SERVICE);
                if (pm != null && pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                    PowerManager.WakeLock w = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "cheeno:prox");
                    w.setReferenceCounted(false);
                    w.acquire();
                    prox = w;
                }
            } else {
                if (aec != null) { try { aec.release(); } catch (Throwable t) {} aec = null; }
                if (prox != null) { try { if (prox.isHeld()) prox.release(); } catch (Throwable t) {} prox = null; }
            }
        } catch (Throwable t) {}
    }

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
                    route(true);
                    extras(true, r);
                    recInfo = "ok" + src;
                    return true;
                } catch (Throwable t) {
                    recInfo = "err:" + t.getClass().getSimpleName();
                }
            }
            return false;
        }
    }

    private AudioTrack trk;

    @UsedByGodot
    public boolean playStart() {
        synchronized (recLock) {
            if (trk != null) return true;
            try {
                int min = AudioTrack.getMinBufferSize(16000, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT);
                if (min <= 0) return false;
                AudioTrack t = new AudioTrack(
                    new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build(),
                    new AudioFormat.Builder().setSampleRate(16000)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build(),
                    min * 4, AudioTrack.MODE_STREAM, AudioManager.AUDIO_SESSION_ID_GENERATE);
                if (t.getState() != AudioTrack.STATE_INITIALIZED) { t.release(); return false; }
                t.play();
                trk = t;
                return true;
            } catch (Throwable e) {
                return false;
            }
        }
    }

    @UsedByGodot
    public void playWrite(String b64) {
        try {
            AudioTrack t = trk;
            if (t == null) return;
            byte[] b = Base64.decode(b64, Base64.NO_WRAP);
            t.write(b, 0, b.length, AudioTrack.WRITE_NON_BLOCKING);
        } catch (Throwable e) {}
    }

    @UsedByGodot
    public void playStop() {
        synchronized (recLock) {
            if (trk == null) return;
            try { trk.stop(); } catch (Throwable e) {}
            try { trk.release(); } catch (Throwable e) {}
            trk = null;
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
            route(false);
            extras(false, null);
        }
    }

    private static final String MEDIA_ORIGIN = "https://cheeno.invalid";
    private android.webkit.WebView mediaView;
    private volatile long mediaToken;
    private final java.util.ArrayDeque<String> mediaEvents = new java.util.ArrayDeque<>();

    private synchronized void mediaEvent(long token, String event) {
        if (token == mediaToken && mediaEvents.size() < 256 && event.length() < 131072) mediaEvents.add(event);
    }
    @UsedByGodot public synchronized String mediaPop() { return mediaEvents.isEmpty() ? "" : mediaEvents.remove(); }
    // UI thread only. Never share a WebView or its JS interface between calls.
    private void releaseMedia() {
        if (mediaView == null) return;
        android.webkit.WebView w = mediaView; mediaView = null;
        w.removeJavascriptInterface("CallHost");
        if (w.getParent() instanceof android.view.ViewGroup) ((android.view.ViewGroup)w.getParent()).removeView(w);
        w.destroy(); route(false);
    }
    @UsedByGodot public synchronized void mediaStart(final String page) {
        final Activity a = getActivity(); final long token = ++mediaToken; mediaEvents.clear();
        if (a == null) { mediaEvent(token,"{\"state\":\"failed\"}"); return; }
        a.runOnUiThread(() -> {
            if (token != mediaToken) return;
            try {
                releaseMedia(); route(true);
                android.webkit.WebView w = new android.webkit.WebView(a); mediaView = w;
                w.getSettings().setJavaScriptEnabled(true); w.getSettings().setAllowFileAccess(false);
                w.getSettings().setAllowContentAccess(false); w.getSettings().setMediaPlaybackRequiresUserGesture(false);
                w.setWebViewClient(new android.webkit.WebViewClient() {
                    @Override public boolean shouldOverrideUrlLoading(android.webkit.WebView v, String url) { return true; }
                    @Override public android.webkit.WebResourceResponse shouldInterceptRequest(android.webkit.WebView v, android.webkit.WebResourceRequest r) {
                        return new android.webkit.WebResourceResponse("text/plain","UTF-8",new java.io.ByteArrayInputStream(new byte[0]));
                    }
                });
                w.setWebChromeClient(new android.webkit.WebChromeClient() {
                    @Override public void onPermissionRequest(android.webkit.PermissionRequest r) {
                        if (token == mediaToken && MEDIA_ORIGIN.equals(r.getOrigin().toString().replaceAll("/$", "")) && java.util.Arrays.asList(r.getResources()).contains(android.webkit.PermissionRequest.RESOURCE_AUDIO_CAPTURE) && a.checkCallingOrSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED) r.grant(new String[]{android.webkit.PermissionRequest.RESOURCE_AUDIO_CAPTURE}); else r.deny();
                    }
                });
                w.addJavascriptInterface(new Object(){ @android.webkit.JavascriptInterface public void emit(String event){ if(event!=null) mediaEvent(token,event); } },"CallHost");
                w.setClickable(false); w.setFocusable(false); w.setImportantForAccessibility(android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO);
                a.addContentView(w,new android.view.ViewGroup.LayoutParams(1,1));
                w.loadDataWithBaseURL(MEDIA_ORIGIN+"/",page,"text/html","UTF-8",null);
            } catch (Exception e) { releaseMedia(); mediaEvent(token,"{\"state\":\"failed\"}"); }
        });
    }
    @UsedByGodot public void mediaCommand(String json) {
        final Activity a=getActivity(); final long token=mediaToken; if(a==null)return;
        final String wire=Base64.encodeToString(json.getBytes(java.nio.charset.StandardCharsets.UTF_8),Base64.NO_WRAP);
        a.runOnUiThread(()->{if(token==mediaToken && mediaView!=null)mediaView.evaluateJavascript("window.cmd('"+wire+"')",null);});
    }
    @UsedByGodot public synchronized void mediaEnd() {
        final long token=++mediaToken; mediaEvents.clear(); Activity a=getActivity();
        if(a!=null)a.runOnUiThread(()->{if(token==mediaToken)releaseMedia();});
    }
    @Override
    public void onMainDestroy() {
        mediaEnd();
        playStop();
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
