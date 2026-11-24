package com.ysdad.ysdad_mise_a_jour;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import java.io.File;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Partie Android du module ysdad_mise_a_jour : autorisation et lancement de l'installeur. */
public class YsdadMiseAJourPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "ysdad_mise_a_jour");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
        context = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "ouvrirUrl":
                result.success(ouvrirUrl((String) call.argument("url")));
                return;
            case "versionCode":
                result.success(versionCode());
                break;
            case "peutInstaller":
                result.success(peutInstaller());
                break;
            case "ouvrirReglageInstallation":
                result.success(ouvrirReglageInstallation());
                break;
            case "installerApk":
                String chemin = call.argument("chemin");
                try {
                    installerApk(chemin);
                    result.success(true);
                } catch (Exception e) {
                    result.error("INSTALLATION", e.getMessage(), null);
                }
                break;
            default:
                result.notImplemented();
        }
    }

    private long versionCode() {
        try {
            PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                return info.getLongVersionCode();
            }
            //noinspection deprecation
            return info.versionCode;
        } catch (PackageManager.NameNotFoundException e) {
            return 0;
        }
    }

    private boolean peutInstaller() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return context.getPackageManager().canRequestPackageInstalls();
        }
        return true;
    }

    private boolean ouvrirReglageInstallation() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false;
        }
        Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + context.getPackageName()));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(intent);
            return true;
        } catch (ActivityNotFoundException e) {
            Intent repli = new Intent(Settings.ACTION_SECURITY_SETTINGS);
            repli.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                context.startActivity(repli);
                return true;
            } catch (ActivityNotFoundException ignored) {
                return false;
            }
        }
    }

    /** Ouvre une page (ex. la fiche Google Play) ; vrai si une appli l'a prise. */
    private boolean ouvrirUrl(String url) {
        if (url == null || url.isEmpty()) return false;
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(intent);
            return true;
        } catch (ActivityNotFoundException ignored) {
            return false;
        }
    }

    private void installerApk(String chemin) {
        File fichier = new File(chemin);
        if (!fichier.exists()) {
            throw new IllegalStateException("Fichier introuvable : " + chemin);
        }
        Uri uri = FileProvider.getUriForFile(context,
                context.getPackageName() + ".ysdadmaj.fileprovider", fichier);
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, "application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(intent);
    }
}
