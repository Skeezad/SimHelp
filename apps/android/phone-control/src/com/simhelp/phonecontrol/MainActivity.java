package com.simhelp.phonecontrol;

import android.Manifest;
import android.app.Activity;
import android.app.role.RoleManager;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CountDownTimer;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.telecom.TelecomManager;
import android.text.InputType;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;
import org.json.JSONArray;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final int ROLE_REQUEST = 100;
    private static final int DEFAULT_APPS_REQUEST = 102;
    private static final int OPTIONAL_SMS_REQUEST = 103;
    private static final int CALL_ACCOUNT_PERMISSION_REQUEST = 104;
    private static final int SHIZUKU_SETUP_REQUEST = 105;
    private static final int DIAGNOSTIC_TXT_REQUEST = 106;
    private static final java.util.concurrent.ExecutorService DIAGNOSTIC_WORKER = Executors.newSingleThreadExecutor();
    private static final String SHIZUKU_STARTUP_CHECKED = "shizuku_startup_checked";
    private static final String OPTIONAL_SMS_PROMPTED = "optional_sms_prompted";
    private static final java.util.concurrent.ExecutorService SMS_SCAN_WORKER =
            Executors.newSingleThreadExecutor();

    private static final int BG = Color.rgb(8, 14, 20);
    private static final int SURFACE = Color.rgb(17, 28, 39);
    private static final int SURFACE_HIGH = Color.rgb(23, 36, 49);
    private static final int BORDER = Color.rgb(42, 58, 73);
    private static final int PRIMARY = Color.rgb(52, 229, 170);
    private static final int CYAN = Color.rgb(73, 231, 224);
    private static final int BLUE = Color.rgb(47, 128, 237);
    private static final int TEXT = Color.rgb(244, 247, 250);
    private static final int MUTED = Color.rgb(166, 179, 193);
    private static final int WARNING = Color.rgb(255, 184, 77);
    private static final int DANGER = Color.rgb(255, 99, 99);

    private enum Page { STATUS, CALLS, DEBUG, SETTINGS }
    private enum Feature { VOWLAN, AGENT, PCM, PUSH, SHIZUKU }

    private FrameLayout contentHost;
    private LinearLayout bottomBar;
    private final List<TextView> navigationItems = new ArrayList<>();
    private Page currentPage = Page.STATUS;
    private HealthTile pcmHealthTile;
    private HealthTile privilegeHealthTile;
    private TextView audioCompatibilityTitle;
    private TextView audioCompatibilityDetails;
    private LiveStatusPoller pcmStatusPoller;
    private boolean resumed;
    private AppUpdatePresenter appUpdates;

    private EditText endpoint;
    private EditText token;
    private EditText number;
    private String selectedMode;
    private TextView status;
    private TextView shizukuStatus;
    private RadioGroup privilegeChannelGroup;
    private final java.util.Map<Integer, PrivilegeChannelPreference.Channel> privilegeChannelIDs
            = new java.util.LinkedHashMap<>();
    private boolean updatingPrivilegeChannel;
	private TextView installerStatus;
    private TextView pairingStatus;
    private TextView pairingCodeView;
    private TextView pairingCountdownView;
    private TextView voBLEAuthenticationStatusView;
    private TextView voBLEPairingCodeView;
    private TextView voBLEDiagnosticsView;
    private TextView voBLEClearCredentialButton;
    private boolean voBLEAuthenticationVisible;
    private LinearLayout debugRows;
    private String lastRenderedDebugLog;
    private String lastRenderedDebugFilter;
    private TextView agentRefreshResult;
    private String agentRefreshMessage = "Click Refresh to see the actual results returned by the Agent";
    private int agentRefreshColor = MUTED;
    private int agentRefreshGeneration;
    private String activeDebugFilter = "all";
    private boolean realtimeLogging = true;
    private boolean agentOnline;
    private String agentDetail = "To be tested";
    private boolean pushConfigured;
    private String pushDetail = "Not checked yet";
    private String pushDiagnostic = "The Agent's Push status has not been read yet";
	private boolean cloudEnabled;
	private boolean cloudRelayConfigured;
	private String cloudLastError = "";
	private boolean avfStartupPromptShown;
	private boolean crashPromptShown;
    private ShizukuStartupPolicy shizukuStartupPolicy;
    private boolean startupSetupPending;
    private boolean startupSetupInFlight;
    private boolean startupSetupCompleted;
    private AlertDialog shizukuStartupDialog;
    private final Runnable startupSetup = () -> {
        if (startupSetupPending) continueStartupSetup();
    };

    private PairingServer pairingServer;
    private CountDownTimer pairingCountdown;
    private String pairingCode = "";
    private long pairingExpiresAt;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable debugRefresh = new Runnable() {
        @Override public void run() {
            if (currentPage == Page.DEBUG && realtimeLogging) {
                refreshDebugLog();
                handler.postDelayed(this, 2_000);
            }
        }
    };
    private final Runnable voBLEAuthenticationRefresh = new Runnable() {
        @Override public void run() {
            if (!voBLEAuthenticationVisible) return;
            renderVoBLEAuthenticationStatus();
            handler.postDelayed(this, 500);
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        appUpdates = new AppUpdatePresenter(this, () -> resumed && startupSetupCompleted
                && !startupSetupPending && !startupSetupInFlight && CallRepository.firstId().isEmpty());
        shizukuStartupPolicy = new ShizukuStartupPolicy(
                state != null && state.getBoolean(SHIZUKU_STARTUP_CHECKED, false));
        pcmStatusPoller = new LiveStatusPoller(() -> {
            ShizukuBridgeManager bridge = ShizukuBridgeManager.get(this);
            bridge.refreshBridgeStatus();
            renderAudioCompatibility();
            refreshPrivilegeTile();
            if (currentPage == Page.SETTINGS) refreshShizukuStatus();
            return bridge.bridgeRunning();
        }, this::renderPCMStatus, new LiveStatusPoller.Scheduler() {
            @Override public void postDelayed(Runnable task, long delayMillis) {
                handler.postDelayed(task, delayMillis);
            }
            @Override public void removeCallbacks(Runnable task) {
                handler.removeCallbacks(task);
            }
        }, 1_000);
        configureWindow();
        setContentView(buildShell());
        showPage(Page.STATUS);
        Uri data = getIntent().getData();
        if (Intent.ACTION_DIAL.equals(getIntent().getAction()) && data != null) {
            showPage(Page.CALLS);
            if (number != null) number.setText(data.getSchemeSpecificPart());
        }
        refreshStatus();
        refreshAgent();
		String[] missingPermissions = RuntimePermissionPolicy.missingPermissions(
				Build.VERSION.SDK_INT,
				checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED,
				checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED,
				checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED,
				checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED,
				checkSelfPermission(Manifest.permission.READ_PHONE_NUMBERS) == PackageManager.PERMISSION_GRANTED,
				Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
						== PackageManager.PERMISSION_GRANTED,
				Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
						== PackageManager.PERMISSION_GRANTED,
				Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE)
						== PackageManager.PERMISSION_GRANTED);
		if (missingPermissions.length > 0) {
            requestPermissions(missingPermissions, 101);
		} else {
			requestOptionalSMSPermission();
		}
    }

	@Override public void onRequestPermissionsResult(
			int requestCode, String[] permissions, int[] grantResults) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults);
		if (requestCode == 101) requestOptionalSMSPermission();
		if (requestCode == 101 && hasVoBLEPermissions()) {
			com.simhelp.phonecontrol.voble.VoBLEGatewayService.start(this);
		}
		if (requestCode == OPTIONAL_SMS_REQUEST) {
			startSMSInboxBaselineIfAuthorized();
			continueStartupSetup();
			if (currentPage == Page.SETTINGS) showPage(Page.SETTINGS);
		}
		if (requestCode == CALL_ACCOUNT_PERMISSION_REQUEST && currentPage == Page.SETTINGS) {
			showPage(Page.SETTINGS);
		}
	}

	private void requestOptionalSMSPermission() {
		boolean granted = checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED;
		boolean prompted = getPreferences(MODE_PRIVATE).getBoolean(OPTIONAL_SMS_PROMPTED, false);
		String[] missing = RuntimePermissionPolicy.optionalInboxPermissions(granted, prompted);
		if (missing.length == 0) {
			continueStartupSetup();
			return;
		}
		getPreferences(MODE_PRIVATE).edit().putBoolean(OPTIONAL_SMS_PROMPTED, true).apply();
		requestPermissions(missing, OPTIONAL_SMS_REQUEST);
	}

	private boolean hasVoBLEPermissions() {
		return Build.VERSION.SDK_INT < 31
				|| (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
				&& checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED);
	}

	private void startSMSInboxBaselineIfAuthorized() {
		if (checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED) {
			SMS_SCAN_WORKER.execute(() -> SMSInboxScanner.scanIfDue(getApplicationContext()));
		}
	}

    private void configureWindow() {
        getWindow().setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        if (Build.VERSION.SDK_INT >= 30) getWindow().setDecorFitsSystemWindows(false);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        getWindow().getDecorView().setSystemUiVisibility(0);
    }

    private View buildShell() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        root.setFitsSystemWindows(false);

        contentHost = new FrameLayout(this);
        root.addView(contentHost, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));

        bottomBar = buildBottomBar();
        root.addView(bottomBar, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(78)));

        root.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
                Insets ime = insets.getInsets(WindowInsets.Type.ime());
                view.setPadding(bars.left, bars.top, bars.right, Math.max(bars.bottom, ime.bottom));
                View focused = getCurrentFocus();
                if (focused instanceof EditText && ime.bottom > 0) focused.post(() ->
                        focused.requestRectangleOnScreen(new android.graphics.Rect(0, 0,
                                focused.getWidth(), focused.getHeight()), false));
            } else {
                view.setPadding(0, insets.getSystemWindowInsetTop(), 0,
                        insets.getSystemWindowInsetBottom());
            }
            return insets;
        });
        return root;
    }

    private LinearLayout buildBottomBar() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER);
        bar.setPadding(dp(10), dp(6), dp(10), dp(8));
        bar.setBackground(rounded(SURFACE, 28, BORDER, 1));
        navigationItems.clear();
        bar.addView(navigationItem("state", android.R.drawable.presence_online, Page.STATUS), weighted());
        bar.addView(navigationItem("call", android.R.drawable.sym_action_call, Page.CALLS), weighted());
        bar.addView(navigationItem("debug", android.R.drawable.ic_menu_info_details, Page.DEBUG), weighted());
        bar.addView(navigationItem("set up", android.R.drawable.ic_menu_preferences, Page.SETTINGS), weighted());
        return bar;
    }

    private TextView navigationItem(String title, int icon, Page page) {
        TextView item = label(title, 12, MUTED, Gravity.CENTER);
        item.setCompoundDrawablesWithIntrinsicBounds(0, icon, 0, 0);
        item.setCompoundDrawableTintList(ColorStateList.valueOf(MUTED));
        item.setCompoundDrawablePadding(dp(3));
        item.setPadding(dp(4), dp(4), dp(4), dp(4));
        item.setOnClickListener(ignored -> showPage(page));
        item.setTag(page);
        navigationItems.add(item);
        return item;
    }

    private void showPage(Page page) {
        if (pcmStatusPoller != null) pcmStatusPoller.stop();
        voBLEAuthenticationVisible = false;
        handler.removeCallbacks(voBLEAuthenticationRefresh);
        voBLEAuthenticationStatusView = null;
        voBLEPairingCodeView = null;
        voBLEDiagnosticsView = null;
        voBLEClearCredentialButton = null;
        pcmHealthTile = null;
        privilegeHealthTile = null;
        shizukuStatus = null;
        privilegeChannelGroup = null;
        audioCompatibilityTitle = null;
        audioCompatibilityDetails = null;
        currentPage = page;
        handler.removeCallbacks(debugRefresh);
        bottomBar.setVisibility(View.VISIBLE);
        contentHost.removeAllViews();
        View content;
        switch (page) {
        case CALLS: content = callsPage(); break;
        case DEBUG: content = debugPage(); break;
        case SETTINGS: content = settingsPage(); break;
        case STATUS:
        default: content = statusPage(); break;
        }
        contentHost.addView(content, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        updateNavigation();
        if (page == Page.DEBUG && realtimeLogging) handler.post(debugRefresh);
        if ((page == Page.STATUS || page == Page.SETTINGS) && resumed) pcmStatusPoller.start();
    }

    private void updateNavigation() {
        for (TextView item : navigationItems) {
            boolean selected = item.getTag() == currentPage;
            int color = selected ? PRIMARY : MUTED;
            item.setTextColor(color);
            item.setTypeface(Typeface.DEFAULT, selected ? Typeface.BOLD : Typeface.NORMAL);
            item.setCompoundDrawableTintList(ColorStateList.valueOf(color));
        }
    }

    private View statusPage() {
        LinearLayout root = pageRoot();
        root.addView(pageTitle("SimHelp Bridge", "Running"));

        boolean paired = VoWLANPairingStore.configured(this);
        LinearLayout hero = card(SURFACE_HIGH, 24);
        hero.setOrientation(LinearLayout.HORIZONTAL);
        hero.setGravity(Gravity.CENTER_VERTICAL);
        hero.setPadding(dp(18), dp(20), dp(18), dp(20));
        ImageView wifi = icon(android.R.drawable.ic_menu_share, CYAN, 54);
        wifi.setBackground(rounded(Color.rgb(20, 80, 73), 28, Color.TRANSPARENT, 0));
        wifi.setPadding(dp(14), dp(14), dp(14), dp(14));
        hero.addView(wifi, new LinearLayout.LayoutParams(dp(58), dp(58)));
        LinearLayout heroCopy = column(dp(14));
        TextView heroTitle = label(
                paired ? (vowlanReady() ? "VoWLAN is ready" : "VoWLAN in preparation") : "VoWLAN not paired yet",
                25, vowlanReady() ? CYAN : WARNING, Gravity.START);
        heroTitle.setTypeface(Typeface.DEFAULT_BOLD);
        heroCopy.addView(heroTitle);
        heroCopy.addView(label(vowlanNetworkLine(), 14, MUTED, Gravity.START));
        hero.addView(heroCopy, weighted());
        hero.setClickable(true);
        hero.setOnClickListener(ignored -> showFeatureDetails(Feature.VOWLAN));
        root.addView(hero, matchWithTop(16));

        String connectionMode = MainScreenPresentation.connectionModeTitle(
                vowlanReady(), cloudEnabled, cloudRelayConfigured, cloudLastError);
        String connectionDetail = MainScreenPresentation.connectionModeDetail(
                vowlanReady(), cloudEnabled, cloudRelayConfigured, cloudLastError);
        int connectionColor = vowlanReady() ? CYAN
                : cloudEnabled && cloudRelayConfigured && cloudLastError.isEmpty() ? BLUE : WARNING;
        LinearLayout connectionCard = card(SURFACE, 18);
        connectionCard.setOrientation(LinearLayout.VERTICAL);
        connectionCard.setPadding(dp(16), dp(14), dp(16), dp(14));
        connectionCard.addView(overline("Current connection mode"));
        TextView connectionTitle = label(connectionMode, 18, connectionColor, Gravity.START);
        connectionTitle.setTypeface(Typeface.DEFAULT_BOLD);
        connectionCard.addView(connectionTitle, matchWithTop(5));
        connectionCard.addView(label(connectionDetail, 13, MUTED, Gravity.START), matchWithTop(5));
        root.addView(connectionCard, matchWithTop(12));

        LinearLayout bluetoothCard = card(SURFACE, 18);
        bluetoothCard.setOrientation(LinearLayout.VERTICAL);
        bluetoothCard.setPadding(dp(16), dp(14), dp(16), dp(14));
        bluetoothCard.addView(overline("Bluetooth call (diagnosis has been desensitized)"));
        bluetoothCard.addView(label(
                com.simhelp.phonecontrol.voble.VoBLEGatewayService.diagnosticsSummary(),
                14, MUTED, Gravity.START), matchWithTop(5));
        root.addView(bluetoothCard, matchWithTop(10));

        LinearLayout firstHealthRow = row();
        HealthTile agentTile = healthTile(
                RuntimeMode.agentLabel(this), agentOnline ? "online" : agentDetail,
                android.R.drawable.ic_menu_manage, agentOnline);
        agentTile.view.setOnClickListener(ignored -> showFeatureDetails(Feature.AGENT));
        firstHealthRow.addView(agentTile.view, weightedWithEnd(5));
        pcmHealthTile = healthTile(
                "PCM audio bridge", pcmBridgeRunning() ? "process running" : "To be started",
                android.R.drawable.ic_media_play, pcmBridgeRunning());
        pcmHealthTile.view.setOnClickListener(ignored -> showFeatureDetails(Feature.PCM));
        firstHealthRow.addView(pcmHealthTile.view, weightedWithStart(5));
        root.addView(firstHealthRow, matchWithTop(12));

        LinearLayout secondHealthRow = row();
        HealthTile pushTile = healthTile(
                "Push / Relay", pushDetail,
                android.R.drawable.stat_notify_sync, pushConfigured);
        pushTile.view.setOnClickListener(ignored -> showFeatureDetails(Feature.PUSH));
        secondHealthRow.addView(pushTile.view, weightedWithEnd(5));
        HealthTile shizukuTile = healthTile(
                "Permission channel", privilegeReady() ? ShizukuBridgeManager.get(this).activePrivilegeLabel() + "Connected" : "To be connected",
                android.R.drawable.ic_lock_idle_lock, privilegeReady());
        privilegeHealthTile = shizukuTile;
        shizukuTile.view.setOnClickListener(ignored -> showFeatureDetails(Feature.SHIZUKU));
        secondHealthRow.addView(shizukuTile.view, weightedWithStart(5));
        root.addView(secondHealthRow, matchWithTop(10));

        root.addView(audioCompatibilityCard(), matchWithTop(12));

        root.addView(modeSelector(), matchWithTop(14));

        TextView pairing = primaryButton(paired ? "Re-pair iPhone" : "Pair a new iPhone", BLUE);
        pairing.setCompoundDrawablesWithIntrinsicBounds(android.R.drawable.ic_input_add, 0, 0, 0);
        pairing.setCompoundDrawableTintList(ColorStateList.valueOf(Color.WHITE));
        pairing.setCompoundDrawablePadding(dp(8));
        pairing.setOnClickListener(ignored -> openPairingPage());
        root.addView(pairing, matchWithTop(14));

        root.addView(sectionTitle("Recent activities"), matchWithTop(22));
        LinearLayout recent = card(SURFACE, 18);
        recent.setPadding(dp(16), dp(14), dp(16), dp(14));
        recent.setOrientation(LinearLayout.HORIZONTAL);
        recent.setGravity(Gravity.CENTER_VERTICAL);
        View dot = new View(this);
        dot.setBackground(rounded(PRIMARY, 7, Color.TRANSPARENT, 0));
        recent.addView(dot, new LinearLayout.LayoutParams(dp(10), dp(10)));
        TextView activity = label(latestActivity(), 14, TEXT, Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams activityParams = weighted();
        activityParams.leftMargin = dp(12);
        recent.addView(activity, activityParams);
        recent.setOnClickListener(ignored -> showPage(Page.DEBUG));
        root.addView(recent, matchWithTop(10));

        status = label("", 12, MUTED, Gravity.START);
        status.setVisibility(View.GONE);
        root.addView(status);
        return scroll(root);
    }

    private View callsPage() {
        LinearLayout root = pageRoot();
        root.addView(pageTitle("call control", null));
        root.addView(description("Samsung Telecom native control; iPhone calls prioritize VoWLAN and are relayed by the cloud when LAN is unavailable."), matchWithTop(8));

        LinearLayout dialCard = card(SURFACE, 24);
        dialCard.setOrientation(LinearLayout.VERTICAL);
        dialCard.setPadding(dp(18), dp(18), dp(18), dp(18));
        dialCard.addView(overline("Dial number"));
        number = input("Enter phone number", InputType.TYPE_CLASS_PHONE);
        dialCard.addView(number, matchWithTop(8));
        TextView call = primaryButton("Dial via System Telecom", PRIMARY);
        call.setTextColor(BG);
        call.setOnClickListener(ignored -> placeSystemCall());
        dialCard.addView(call, matchWithTop(14));
        root.addView(dialCard, matchWithTop(18));

        root.addView(sectionTitle("Current call"), matchWithTop(22));
        LinearLayout actions = row();
        TextView answer = secondaryButton("Samsung answer");
        answer.setOnClickListener(ignored -> localCall("answer"));
        TextView hangup = secondaryButton("Hang up the call");
        hangup.setTextColor(DANGER);
        hangup.setOnClickListener(ignored -> localCall("end"));
        actions.addView(answer, weightedWithEnd(5));
        actions.addView(hangup, weightedWithStart(5));
        root.addView(actions, matchWithTop(10));

        LinearLayout roleCard = card(SURFACE, 20);
        roleCard.setOrientation(LinearLayout.VERTICAL);
        roleCard.setPadding(dp(16), dp(14), dp(16), dp(14));
        roleCard.addView(label(roleText(), 15, TEXT, Gravity.START));
        roleCard.addView(description("Emergency calls are always handled by the system's pre-installed dialer."), matchWithTop(4));
        roleCard.setOnClickListener(ignored -> requestDialerRole());
        root.addView(roleCard, matchWithTop(18));
        return scroll(root);
    }

    private View debugPage() {
        LinearLayout root = pageRoot();
        root.addView(pageTitle("Debug Diagnosis", null));
        root.addView(smsAssistCard(), matchWithTop(14));
		if (CrashReportStore.hasReport(getFilesDir())) {
			LinearLayout crashCard = card(Color.rgb(57, 31, 36), 22);
			crashCard.setOrientation(LinearLayout.VERTICAL);
			crashCard.setPadding(dp(16), dp(15), dp(16), dp(15));
			TextView title = label("Last crash detected", 16, DANGER, Gravity.START);
			title.setTypeface(Typeface.DEFAULT_BOLD);
			crashCard.addView(title);
			crashCard.addView(label("The report is desensitized and saved locally, and will not leave the device until you click Send.",
					12, MUTED, Gravity.START), matchWithTop(4));
			LinearLayout crashActions = row();
			TextView send = secondaryButton("Send crash report");
			send.setTextColor(PRIMARY);
			send.setOnClickListener(ignored -> shareCrashReport());
			TextView remove = secondaryButton("Delete report");
			remove.setTextColor(DANGER);
			remove.setOnClickListener(ignored -> {
				CrashReportStore.clear(getFilesDir());
				toast("Crash report has been deleted");
				showPage(Page.DEBUG);
			});
			crashActions.addView(send, weightedWithEnd(5));
			crashActions.addView(remove, weightedWithStart(5));
			crashCard.addView(crashActions, matchWithTop(12));
			root.addView(crashCard, matchWithTop(12));
		}
        root.addView(debugFilters(), matchWithTop(14));

        LinearLayout logCard = card(SURFACE, 22);
        logCard.setOrientation(LinearLayout.VERTICAL);
        logCard.setPadding(dp(12), dp(4), dp(12), dp(4));
        debugRows = column(0);
        lastRenderedDebugLog = null;
        lastRenderedDebugFilter = null;
        logCard.addView(debugRows);
        root.addView(logCard, matchWithTop(14));

        LinearLayout actions = row();
        TextView copy = secondaryButton("Copy log");
        copy.setOnClickListener(ignored -> copyDebugLog());
        TextView export = secondaryButton("Export diagnostics");
        export.setOnClickListener(ignored -> exportDebugLog());
        actions.addView(copy, weightedWithEnd(5));
        actions.addView(export, weightedWithStart(5));
        root.addView(actions, matchWithTop(12));

        TextView watchdogExport = secondaryButton("Save Audio Watchdog TXT");
        watchdogExport.setOnClickListener(ignored -> {
            Intent document = new Intent(Intent.ACTION_CREATE_DOCUMENT);
            document.addCategory(Intent.CATEGORY_OPENABLE);
            document.setType("text/plain");
            document.putExtra(Intent.EXTRA_TITLE, "SimHelp-audio-watchdog-" + System.currentTimeMillis() + ".txt");
            try { startActivityForResult(document, DIAGNOSTIC_TXT_REQUEST); }
            catch (RuntimeException error) { toast("Unable to open file save window, please use copy log"); }
        });
        root.addView(watchdogExport, matchWithTop(8));
        root.addView(label("During remote calls, recheck the mute status every 2 seconds and verify again after controlled repair. Desensitized VERBOSE snapshots are automatically saved locally; system flags do not guarantee actual speaker silence.",
                12, MUTED, Gravity.START), matchWithTop(8));

        LinearLayout live = card(SURFACE, 20);
        live.setOrientation(LinearLayout.HORIZONTAL);
        live.setGravity(Gravity.CENTER_VERTICAL);
        live.setPadding(dp(16), dp(14), dp(12), dp(14));
        LinearLayout liveCopy = column(0);
        liveCopy.addView(label("real time recording", 15, TEXT, Gravity.START));
        liveCopy.addView(label("Automatically refresh the latest log information", 12, MUTED, Gravity.START));
        live.addView(liveCopy, weighted());
        Switch toggle = new Switch(this);
        toggle.setChecked(realtimeLogging);
        toggle.setThumbTintList(ColorStateList.valueOf(PRIMARY));
        toggle.setOnCheckedChangeListener((ignored, enabled) -> {
            realtimeLogging = enabled;
            handler.removeCallbacks(debugRefresh);
            if (enabled) handler.post(debugRefresh);
        });
        live.addView(toggle);
        root.addView(live, matchWithTop(12));

        LinearLayout destructive = row();
        TextView refresh = secondaryButton("Refresh now");
        refresh.setOnClickListener(ignored -> refreshDebugLog());
        TextView clear = secondaryButton("Clear log");
        clear.setTextColor(DANGER);
        clear.setOnClickListener(ignored -> { BridgeLog.clear(); refreshDebugLog(); });
        destructive.addView(refresh, weightedWithEnd(5));
        destructive.addView(clear, weightedWithStart(5));
        root.addView(destructive, matchWithTop(10));
        refreshDebugLog();
        return scroll(root);
    }

    private View settingsPage() {
        LinearLayout root = pageRoot();
        root.addView(pageTitle("set up", null));

        boolean standaloneRuntime = RuntimeMode.isStandalone(this);
        root.addView(sectionTitle(RuntimeMode.agentLabel(this)), matchWithTop(18));
        LinearLayout agentCard = card(SURFACE, 22);
        agentCard.setOrientation(LinearLayout.VERTICAL);
        agentCard.setPadding(dp(16), dp(16), dp(16), dp(16));
        if (standaloneRuntime) {
            agentCard.addView(label("The Agent runs in the foreground service of this APK and does not use AVF, Linux Terminal, 8575 or 8576.",
                    14, TEXT, Gravity.START));
        } else {
            endpoint = input("Agent address", InputType.TYPE_CLASS_TEXT);
            endpoint.setText(AppConfig.endpoint(this));
            agentCard.addView(endpoint);
            token = input("control token", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
            token.setText(AppConfig.token(this));
            agentCard.addView(token, matchWithTop(10));
        }
        selectedMode = AppConfig.mode(this);
        agentCard.addView(modeSelector(), matchWithTop(12));
        TextView save = primaryButton(standaloneRuntime ? "Save the schema and start the built-in Agent" : "Save the configuration and start the daemon", BLUE);
        save.setOnClickListener(ignored -> saveConfiguration());
        agentCard.addView(save, matchWithTop(12));
        root.addView(agentCard, matchWithTop(10));

        root.addView(sectionTitle("Default calling card"), matchWithTop(22));
        LinearLayout callAccountCard = card(SURFACE, 22);
        callAccountCard.setOrientation(LinearLayout.VERTICAL);
        callAccountCard.setPadding(dp(16), dp(16), dp(16), dp(16));
        DefaultCallAccount.Snapshot accounts = DefaultCallAccount.snapshot(this);
        String accountKey = DefaultCallAccount.selectedKey(this);
        boolean available = accountKey.isEmpty() || accounts.accounts().stream()
                .anyMatch(account -> account.key().equals(accountKey));
        callAccountCard.addView(label(DefaultCallAccount.selectedLabel(this)
                + (available ? "" : "· Currently unavailable"), 14, available ? TEXT : WARNING, Gravity.START));
        callAccountCard.addView(description("Used for SimHelp Bluetooth, VoWLAN and cloud dialing without changing the system calling card or SMS card."
                + "Dialing will stop when the specified card is closed or removed, please select again."), matchWithTop(6));
        if (!accounts.error().isEmpty()) {
            callAccountCard.addView(description(accounts.error()), matchWithTop(6));
        } else if (accounts.accounts().isEmpty()) {
            callAccountCard.addView(description("No cellular calling card enabled"), matchWithTop(6));
        }
        TextView chooseAccount = secondaryButton("Select default calling card");
        chooseAccount.setOnClickListener(ignored -> chooseDefaultCallAccount());
        callAccountCard.addView(chooseAccount, matchWithTop(10));
        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            TextView grantAccountPermission = secondaryButton("Authorization to read calling card");
            grantAccountPermission.setOnClickListener(ignored -> requestPermissions(
                    new String[] {Manifest.permission.READ_PHONE_STATE}, CALL_ACCOUNT_PERMISSION_REQUEST));
            callAccountCard.addView(grantAccountPermission, matchWithTop(10));
        }
        root.addView(callAccountCard, matchWithTop(10));

        root.addView(sectionTitle("VoBLE Bluetooth certification"), matchWithTop(22));
        LinearLayout voBLECard = card(SURFACE, 22);
        voBLECard.setOrientation(LinearLayout.VERTICAL);
        voBLECard.setPadding(dp(16), dp(16), dp(16), dp(16));
        boolean voBLEPaired = com.simhelp.phonecontrol.voble.VoBLEGatewayService
                .hasStoredCredential(this);
        voBLECard.addView(label(voBLEPaired ? "iPhone authentication credentials saved" : "Authentication credentials not saved yet",
                14, voBLEPaired ? PRIMARY : MUTED, Gravity.START));
        voBLECard.addView(description("Manage six-digit security code authentication, old credential recovery and dual-end unpairing."),
                matchWithTop(6));
        TextView configureVoBLE = secondaryButton("Open VoBLE authentication configuration");
        configureVoBLE.setOnClickListener(ignored -> openVoBLEAuthenticationPage());
        voBLECard.addView(configureVoBLE, matchWithTop(10));
        root.addView(voBLECard, matchWithTop(10));

		root.addView(sectionTitle("SMS inbox secrets"), matchWithTop(22));
		LinearLayout smsCard = card(SURFACE, 22);
		smsCard.setOrientation(LinearLayout.VERTICAL);
		smsCard.setPadding(dp(16), dp(16), dp(16), dp(16));
		boolean inboxGranted = checkSelfPermission(Manifest.permission.READ_SMS)
				== PackageManager.PERMISSION_GRANTED;
		smsCard.addView(label(inboxGranted ? "Authorized · Scan only newly received text messages"
				: "Unauthorized · Continue to use SMS broadcast reception", 14, TEXT, Gravity.START));
		smsCard.addView(description("Optional permission; used to retrieve new text messages when the broadcast is not delivered, and does not import historical text messages."), matchWithTop(6));
		if (!inboxGranted) {
			TextView permissionAction = secondaryButton("Authorize reading text messages in system settings");
			permissionAction.setOnClickListener(ignored -> startActivity(new Intent(
					Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
					Uri.parse("package:" + getPackageName()))));
			smsCard.addView(permissionAction, matchWithTop(10));
		}
		root.addView(smsCard, matchWithTop(10));

		if (!standaloneRuntime) {
		root.addView(sectionTitle("AVF Linux first installation"), matchWithTop(22));
		LinearLayout bootstrapCard = card(SURFACE, 22);
		bootstrapCard.setOrientation(LinearLayout.VERTICAL);
		bootstrapCard.setPadding(dp(16), dp(16), dp(16), dp(16));
		AVFEnvironmentDetector.Snapshot avf = AVFEnvironmentDetector.inspect(this);
		bootstrapCard.addView(label(avfEnvironmentSummary(avf), 14, TEXT, Gravity.START));
		TextView installCommand = label(AVFStartupPolicy.installCommand(), 12, MUTED, Gravity.START);
		installCommand.setTextIsSelectable(true);
		installCommand.setPadding(0, dp(10), 0, dp(4));
		bootstrapCard.addView(installCommand);
		LinearLayout bootstrapActions = row();
		TextView copyInstall = secondaryButton("Copy the one-click installation command");
		copyInstall.setOnClickListener(ignored -> copyAVFInstallCommand());
		TextView openLinux = secondaryButton(avf.state() == AVFStartupPolicy.State.RUNNING
				? "Open Linux Terminal" : "Start Linux Terminal");
		openLinux.setOnClickListener(ignored -> openAVFTerminalOrSettings());
		bootstrapActions.addView(copyInstall, weightedWithEnd(5));
		bootstrapActions.addView(openLinux, weightedWithStart(5));
		bootstrapCard.addView(bootstrapActions, matchWithTop(10));
		TextView developerOptions = secondaryButton("Open developer options");
		developerOptions.setOnClickListener(ignored -> AVFEnvironmentActions.openDeveloperOptions(this));
		bootstrapCard.addView(developerOptions, matchWithTop(10));
		root.addView(bootstrapCard, matchWithTop(10));

		root.addView(sectionTitle("AVF Agent management"), matchWithTop(22));
		LinearLayout installerCard = card(SURFACE, 22);
		installerCard.setOrientation(LinearLayout.VERTICAL);
		installerCard.setPadding(dp(16), dp(16), dp(16), dp(16));
		installerStatus = label("Reading installerd status...", 13, MUTED, Gravity.START);
		installerCard.addView(installerStatus);
		TextView updateAgent = primaryButton("Check and install the latest Agent", BLUE);
		updateAgent.setOnClickListener(ignored -> runAgentMaintenance("update"));
		installerCard.addView(updateAgent, matchWithTop(12));
		LinearLayout installerActions = row();
		TextView repairAgent = secondaryButton("Fix current version");
		repairAgent.setOnClickListener(ignored -> runAgentMaintenance("repair"));
		TextView rollbackAgent = secondaryButton("Roll back to previous version");
		rollbackAgent.setTextColor(WARNING);
		rollbackAgent.setOnClickListener(ignored -> runAgentMaintenance("rollback"));
		installerActions.addView(repairAgent, weightedWithEnd(5));
		installerActions.addView(rollbackAgent, weightedWithStart(5));
		installerCard.addView(installerActions, matchWithTop(10));
		root.addView(installerCard, matchWithTop(10));
		refreshInstallerStatus();
		}

        root.addView(sectionTitle("Shizuku/Root Permissions and PCM Bridge"), matchWithTop(22));
        LinearLayout shizukuCard = card(SURFACE, 22);
        shizukuCard.setOrientation(LinearLayout.VERTICAL);
        shizukuCard.setPadding(dp(16), dp(16), dp(16), dp(16));
        shizukuStatus = label("", 14, TEXT, Gravity.START);
        shizukuCard.addView(shizukuStatus);
        shizukuCard.addView(description("Call audio bridge requires Shizuku or KernelSU Root. Automatic mode gives priority to Root, failing which returns to Shizuku."), matchWithTop(6));

        privilegeChannelGroup = new RadioGroup(this);
        privilegeChannelGroup.setOrientation(RadioGroup.VERTICAL);
        privilegeChannelGroup.setId(View.generateViewId());
        privilegeChannelIDs.clear();
        PrivilegeChannelPreference.Channel currentChannel = PrivilegeChannelPreference.get(this);
        for (PrivilegeChannelPreference.Channel channel : PrivilegeChannelPreference.Channel.values()) {
            RadioButton option = new RadioButton(this);
            option.setText(PrivilegeChannelPreference.label(channel));
            option.setTextColor(TEXT);
            option.setButtonTintList(ColorStateList.valueOf(PRIMARY));
            option.setId(View.generateViewId());
            privilegeChannelIDs.put(option.getId(), channel);
            privilegeChannelGroup.addView(option);
            if (channel == currentChannel) option.setChecked(true);
        }
        privilegeChannelGroup.setOnCheckedChangeListener((group, checkedId) -> {
            if (updatingPrivilegeChannel) return;
            PrivilegeChannelPreference.Channel selected = privilegeChannelIDs.get(checkedId);
            if (selected == null) return;
            ShizukuBridgeManager.get(this).setPrivilegeChannel(selected);
            refreshShizukuStatus();
            toast("Permission channel has been switched");
        });
        shizukuCard.addView(privilegeChannelGroup, matchWithTop(8));
        shizukuCard.addView(description("Switching channels will rebuild the PCM bridge; selecting Root will request KernelSU authorization for the first time."), matchWithTop(4));

        LinearLayout shizukuActions = row();
        TextView authorize = secondaryButton("Authorize and start");
        authorize.setOnClickListener(ignored -> {
            ShizukuBridgeManager.get(this).requestPermission();
            refreshShizukuStatus();
        });
        TextView open = secondaryButton("Open Shizuku");
        open.setOnClickListener(ignored -> {
            ShizukuBridgeManager.get(this).openShizuku();
            refreshShizukuStatus();
        });
        shizukuActions.addView(authorize, weightedWithEnd(5));
        shizukuActions.addView(open, weightedWithStart(5));
        shizukuCard.addView(shizukuActions, matchWithTop(12));

        LinearLayout rootActions = row();
        TextView rootAuth = secondaryButton("Root authorization/retry");
        rootAuth.setOnClickListener(ignored -> {
            ShizukuBridgeManager.get(this).requestRootPermission();
            refreshShizukuStatus();
            toast("Requesting root authorization");
        });
        TextView refreshChannel = secondaryButton("Refresh channel status");
        refreshChannel.setOnClickListener(ignored -> refreshShizukuStatus());
        rootActions.addView(rootAuth, weightedWithEnd(5));
        rootActions.addView(refreshChannel, weightedWithStart(5));
        shizukuCard.addView(rootActions, matchWithTop(10));
        root.addView(shizukuCard, matchWithTop(10));

        root.addView(sectionTitle("Private network and ports"), matchWithTop(22));
        LinearLayout networkCard = card(SURFACE, 22);
        networkCard.setOrientation(LinearLayout.VERTICAL);
        networkCard.setPadding(dp(16), dp(16), dp(16), dp(16));
        networkCard.addView(description("Built-in support for 10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10 (Tailscale)."
                + "If the LAN uses another network segment, please add it here, such as 30.0.0.0/8."), matchWithTop(0));
        EditText rangesInput = new EditText(this);
        rangesInput.setText(NetworkSettings.rangesText(this));
        rangesInput.setHint("For example 30.0.0.0/8, 100.64.0.0/10");
        rangesInput.setTextColor(TEXT);
        rangesInput.setHintTextColor(MUTED);
        rangesInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        networkCard.addView(rangesInput, matchWithTop(10));

        networkCard.addView(description("Preferred ports (1024–65535; when occupied or restricted, free ports will be automatically used."
                + "Bonjour advertises the actual port). Leave 0 for automatic selection."), matchWithTop(12));
        EditText controlInput = portField("VoWLAN control port", NetworkSettings.controlPort(this));
        networkCard.addView(controlInput, matchWithTop(8));
        EditText pcmInput = portField("VoWLAN PCM port", NetworkSettings.pcmPort(this));
        networkCard.addView(pcmInput, matchWithTop(6));
        EditText pairingInput = portField("Paired port (0 = automatic)", NetworkSettings.pairingPort(this));
        networkCard.addView(pairingInput, matchWithTop(6));

        TextView saveNetwork = primaryButton("Save network and port settings", BLUE);
        saveNetwork.setOnClickListener(ignored -> {
            String text = rangesInput.getText().toString().trim();
            java.util.List<String> invalid = new java.util.ArrayList<>();
            for (String item : text.split("[,\\s]+")) {
                if (!item.isEmpty() && PrivateNetworkPolicy.parse(item) == null) invalid.add(item);
            }
            if (!invalid.isEmpty()) {
                toast("Invalid network segment format:" + String.join(", ", invalid));
                return;
            }
            int control = parsePort(controlInput, NetworkSettings.DEFAULT_CONTROL_PORT);
            int pcm = parsePort(pcmInput, NetworkSettings.DEFAULT_PCM_PORT);
            int pairing = parsePort(pairingInput, NetworkSettings.DEFAULT_PAIRING_PORT);
            if (control < 0 || pcm < 0 || pairing < 0) {
                toast("The port needs to be between 1024–65535, and the paired port can be filled in with 0");
                return;
            }
            if (control == pcm) {
                toast("The control port and PCM port cannot be the same");
                return;
            }
            NetworkSettings.setRangesText(this, text);
            NetworkSettings.setPorts(this, control, pcm, pairing);
            VoWLANGatewayService.restartAfterSettingsChange(this);
            toast("Saved; VoWLAN gateway is restarting on new port");
        });
        networkCard.addView(saveNetwork, matchWithTop(14));
        root.addView(networkCard, matchWithTop(10));

        root.addView(sectionTitle("Telephone Roles and Diagnostics"), matchWithTop(22));
        TextView dialer = secondaryButton("Set as default phone app");
        dialer.setOnClickListener(ignored -> requestDialerRole());
        root.addView(dialer, matchWithTop(10));
        TextView agent = secondaryButton("Refresh Agent status");
        agent.setOnClickListener(ignored -> refreshAgent(true));
        root.addView(agent, matchWithTop(10));
        agentRefreshResult = label(agentRefreshMessage, 12, agentRefreshColor, Gravity.START);
        agentRefreshResult.setPadding(dp(12), dp(8), dp(12), dp(8));
        agentRefreshResult.setBackground(rounded(SURFACE, 12, BORDER, 1));
        root.addView(agentRefreshResult, matchWithTop(6));
        TextView heartbeat = secondaryButton("Send cloud heartbeat immediately");
        TextView heartbeatResult = description("Only checks registration and heartbeat, does not dial or send text messages; sending is prohibited in pure local mode.");
        heartbeat.setOnClickListener(ignored -> {
            if (!heartbeat.isEnabled()) return;
            heartbeat.setEnabled(false);
            heartbeatResult.setText("Sending, please wait...");
            new Thread(() -> {
                String message;
                try {
                    if (RelayEgressGate.shared.isBlocked()) throw new IllegalStateException("Pure local mode is turned on, prohibiting sending cloud heartbeats");
                    if (RuntimeMode.isStandalone(this)) StandaloneAgentService.sendManualHeartbeat();
                    else if (!new JSONObject(new AgentClient(this).sendHeartbeat()).optBoolean("accepted", false))
                        throw new IllegalStateException("The Agent has not confirmed that the heartbeat has been accepted. Please upgrade the Agent and try again.");
                    message = "Relay has accepted the heartbeat, please re-run the cloud self-test on iPhone. This result does not mean that the call link has passed.";
                } catch (Exception error) {
                    message = "Heartbeat sending failed:" + DebugRedactor.sanitize(String.valueOf(error.getMessage()));
                    BridgeLog.error("manual_heartbeat_failed", error);
                }
                final String result = message;
                runOnUiThread(() -> { heartbeat.setEnabled(true); heartbeatResult.setText(result); });
            }, "SimHelpManualHeartbeat").start();
        });
        root.addView(heartbeat, matchWithTop(10));
        root.addView(heartbeatResult, matchWithTop(6));

        CheckBox debugEnabled = new CheckBox(this);
        debugEnabled.setText("Enable Debug mode");
        debugEnabled.setTextColor(TEXT);
        debugEnabled.setButtonTintList(ColorStateList.valueOf(PRIMARY));
        debugEnabled.setChecked(AppConfig.debugEnabled(this));
        debugEnabled.setOnCheckedChangeListener((ignored, enabled) -> {
            BridgeLog.setDebugEnabled(this, enabled);
            toast(enabled ? "Debug log is enabled" : "Debug log is closed");
        });
        root.addView(debugEnabled, matchWithTop(14));
        root.addView(sectionTitle("about"), matchWithTop(22));
        LinearLayout aboutCard = card(SURFACE, 22);
        aboutCard.setOrientation(LinearLayout.VERTICAL);
        aboutCard.setPadding(dp(16), dp(16), dp(16), dp(16));
        aboutCard.addView(label("SimHelp · " + RuntimeMode.agentLabel(this), 16, TEXT, Gravity.START));
        TextView version = label("Version" + AppInformation.version(this), 14, MUTED, Gravity.START);
        version.setTextIsSelectable(true);
        aboutCard.addView(version, matchWithTop(6));
        TextView notes = secondaryButton("Updates to the current version");
        notes.setOnClickListener(ignored -> appUpdates.showNotes(() -> {}));
        aboutCard.addView(notes, matchWithTop(10));
        TextView appCheck = secondaryButton("Check for app updates");
        appCheck.setOnClickListener(ignored -> appUpdates.check(true));
        aboutCard.addView(appCheck, matchWithTop(10));
        aboutCard.addView(description(appUpdates.status()), matchWithTop(6));
        TextView repository = secondaryButton("GitHub repository");
        repository.setOnClickListener(ignored -> openProjectURL(AppInformation.REPOSITORY_URL));
        aboutCard.addView(repository, matchWithTop(12));
        TextView releases = secondaryButton("Version release and download");
        releases.setOnClickListener(ignored -> openProjectURL(AppInformation.RELEASES_URL));
        aboutCard.addView(releases, matchWithTop(10));
        root.addView(aboutCard, matchWithTop(10));

        root.addView(sectionTitle("feedback"), matchWithTop(22));
        LinearLayout feedbackCard = card(SURFACE, 22);
        feedbackCard.setOrientation(LinearLayout.VERTICAL);
        feedbackCard.setPadding(dp(16), dp(16), dp(16), dp(16));
        feedbackCard.addView(description("Only manually upload desensitization logs to Notion; do not upload SMS content or keys."));
        EditText feedbackDescription = input("User description (optional)", InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        feedbackDescription.setSingleLine(false);
        feedbackDescription.setMinLines(2);
        feedbackDescription.setText(FeedbackUploader.description(this));
        feedbackCard.addView(feedbackDescription, matchWithTop(10));
        feedbackCard.addView(feedbackPasteButton(feedbackDescription, "Paste into description"), matchWithTop(6));
        EditText feedbackRemark = input("Remarks (optional)", InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        feedbackRemark.setSingleLine(false);
        feedbackRemark.setMinLines(2);
        feedbackRemark.setText(FeedbackUploader.remark(this));
        feedbackCard.addView(feedbackRemark, matchWithTop(8));
        feedbackCard.addView(feedbackPasteButton(feedbackRemark, "Paste into notes"), matchWithTop(6));
        TextView uploadFeedback = secondaryButton("Save and upload feedback now");
        uploadFeedback.setOnClickListener(ignored -> {
            FeedbackUploader.setFields(this, feedbackDescription.getText().toString(),
                    feedbackRemark.getText().toString());
            FeedbackUploader.submit(this, "manual", "manual:" + UUID.randomUUID());
            toast("Feedback has been submitted and is being uploaded");
        });
        feedbackCard.addView(uploadFeedback, matchWithTop(12));
        root.addView(feedbackCard, matchWithTop(10));
        refreshShizukuStatus();
        return scroll(root);
    }

    private TextView feedbackPasteButton(EditText input, String title) {
        input.setLongClickable(true);
        input.setSelectAllOnFocus(false);
        input.setGravity(Gravity.TOP | Gravity.START);
        TextView button = secondaryButton(title);
        button.setOnClickListener(ignored -> {
            ClipboardManager clipboard = getSystemService(ClipboardManager.class);
            android.content.ClipData clip = clipboard == null ? null : clipboard.getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0 || clip.getItemAt(0).getText() == null) {
                toast("Clipboard has no text to paste"); return;
            }
            int start = Math.max(0, input.getSelectionStart());
            int end = Math.max(0, input.getSelectionEnd());
            input.getText().replace(Math.min(start, end), Math.max(start, end), clip.getItemAt(0).getText());
            input.requestFocus();
        });
        return button;
    }

    private void openProjectURL(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (android.content.ActivityNotFoundException ignored) {
            toast("There is no browser that can open the web page");
        }
    }

    private void openPairingPage() {
        handler.removeCallbacks(debugRefresh);
        voBLEAuthenticationVisible = false;
        handler.removeCallbacks(voBLEAuthenticationRefresh);
        bottomBar.setVisibility(View.GONE);
        contentHost.removeAllViews();
        contentHost.addView(pairingPage(), new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        startPairing();
    }

    private void openVoBLEAuthenticationPage() {
        handler.removeCallbacks(debugRefresh);
        handler.removeCallbacks(voBLEAuthenticationRefresh);
        voBLEAuthenticationVisible = true;
        bottomBar.setVisibility(View.GONE);
        contentHost.removeAllViews();
        contentHost.addView(voBLEAuthenticationPage(), new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        handler.post(voBLEAuthenticationRefresh);
    }

    private View voBLEAuthenticationPage() {
        LinearLayout root = pageRoot();
        TextView back = label("‹", 40, TEXT, Gravity.START);
        back.setContentDescription("Return to settings");
        back.setOnClickListener(ignored -> {
            bottomBar.setVisibility(View.VISIBLE);
            showPage(Page.SETTINGS);
        });
        root.addView(back, new LinearLayout.LayoutParams(dp(56), dp(52)));

        TextView title = label("VoBLE certification", 30, TEXT, Gravity.START);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title, matchWithTop(8));
        root.addView(description("Bluetooth is a standalone connection mode; authentication credentials do not affect VoWLAN or Cloud Relay."),
                matchWithTop(6));

        boolean permissions = hasVoBLEPermissions();
        boolean paired = com.simhelp.phonecontrol.voble.VoBLEGatewayService
                .hasStoredCredential(this);
        LinearLayout statusCard = card(SURFACE, 22);
        statusCard.setOrientation(LinearLayout.VERTICAL);
        statusCard.setPadding(dp(16), dp(16), dp(16), dp(16));
        statusCard.addView(overline("Certification status"));
        voBLEAuthenticationStatusView = label(
                MainScreenPresentation.voBLEAuthenticationStatus(
                        paired,
                        com.simhelp.phonecontrol.voble.VoBLEGatewayService.isAuthenticated(),
                        com.simhelp.phonecontrol.voble.VoBLEGatewayService.pendingPairingCode()),
                19, paired ? PRIMARY : WARNING, Gravity.START);
        statusCard.addView(voBLEAuthenticationStatusView, matchWithTop(7));
        statusCard.addView(label(permissions ? "Bluetooth permission: authorized" : "Bluetooth permissions: authorization required",
                13, permissions ? MUTED : WARNING, Gravity.START), matchWithTop(7));
        voBLEDiagnosticsView = label(
                com.simhelp.phonecontrol.voble.VoBLEGatewayService.diagnosticsSummary(),
                13, MUTED, Gravity.START);
        statusCard.addView(voBLEDiagnosticsView, matchWithTop(7));
        statusCard.addView(overline("Six-digit security code"), matchWithTop(18));
        voBLEPairingCodeView = label(
                MainScreenPresentation.voBLEPairingCode(
                        com.simhelp.phonecontrol.voble.VoBLEGatewayService.pendingPairingCode()),
                28, MUTED, Gravity.CENTER);
        voBLEPairingCodeView.setTypeface(Typeface.create(Typeface.MONOSPACE, Typeface.BOLD));
        statusCard.addView(voBLEPairingCodeView, matchWithTop(8));
        root.addView(statusCard, matchWithTop(18));

        LinearLayout flowCard = card(SURFACE, 22);
        flowCard.setOrientation(LinearLayout.VERTICAL);
        flowCard.setPadding(dp(16), dp(16), dp(16), dp(16));
        flowCard.addView(overline("Certification process"));
        flowCard.addView(label("1. iPhone scans and connects to this Android Agent\\n"
                        + "2. Verify the same six-digit security code at both ends\\n"
                        + "3. After confirmation, save the application layer key and enable dial-up and PCM audio",
                14, TEXT, Gravity.START), matchWithTop(8));
        flowCard.addView(description("If the iPhone displays already paired or the authentication fails, it means that the old keys at both ends are inconsistent."
                + "Please clear old credentials on this page before returning to iPhone to pair again."), matchWithTop(10));
        root.addView(flowCard, matchWithTop(12));

        TextView restart = secondaryButton("Restart VoBLE service");
        restart.setOnClickListener(ignored -> {
            com.simhelp.phonecontrol.voble.VoBLEGatewayService.start(this);
            toast("VoBLE service started");
            openVoBLEAuthenticationPage();
        });
        root.addView(restart, matchWithTop(16));

        voBLEClearCredentialButton = secondaryButton("Clear VoBLE pairing credentials");
        voBLEClearCredentialButton.setTextColor(paired ? DANGER : MUTED);
        voBLEClearCredentialButton.setEnabled(paired);
        voBLEClearCredentialButton.setOnClickListener(ignored -> new AlertDialog.Builder(this)
                .setTitle("Clear old VoBLE pairing?")
                .setMessage("Only deletes the Bluetooth authentication key and ends the current VoBLE session; does not clear VoWLAN, Relay, or call logs.")
                .setPositiveButton("Clear and re-pair", (dialog, which) -> {
                    com.simhelp.phonecontrol.voble.VoBLEGatewayService.clearStoredCredential(this);
                    handler.postDelayed(() -> {
                        toast("VoBLE old credentials cleared");
                        openVoBLEAuthenticationPage();
                    }, 150);
                })
                .setNegativeButton("Cancel", null)
                .show());
        root.addView(voBLEClearCredentialButton, matchWithTop(10));
        return scroll(root);
    }

    private void renderVoBLEAuthenticationStatus() {
        boolean stored = com.simhelp.phonecontrol.voble.VoBLEGatewayService
                .hasStoredCredential(this);
        boolean authenticated = com.simhelp.phonecontrol.voble.VoBLEGatewayService.isAuthenticated();
        String pairingCode = com.simhelp.phonecontrol.voble.VoBLEGatewayService.pendingPairingCode();
        if (voBLEAuthenticationStatusView != null) {
            voBLEAuthenticationStatusView.setText(MainScreenPresentation.voBLEAuthenticationStatus(
                    stored, authenticated, pairingCode));
            voBLEAuthenticationStatusView.setTextColor(
                    authenticated || stored ? PRIMARY : WARNING);
        }
        if (voBLEPairingCodeView != null) {
            String formatted = MainScreenPresentation.formatPairingCode(pairingCode);
            voBLEPairingCodeView.setText(MainScreenPresentation.voBLEPairingCode(pairingCode));
            voBLEPairingCodeView.setTextColor("--- ---".equals(formatted) ? MUTED : PRIMARY);
        }
        if (voBLEDiagnosticsView != null) {
            voBLEDiagnosticsView.setText(
                    com.simhelp.phonecontrol.voble.VoBLEGatewayService.diagnosticsSummary());
        }
        if (voBLEClearCredentialButton != null) {
            voBLEClearCredentialButton.setEnabled(stored);
            voBLEClearCredentialButton.setTextColor(stored ? DANGER : MUTED);
        }
    }

    private View pairingPage() {
        LinearLayout root = pageRoot();
        TextView back = label("‹", 40, TEXT, Gravity.START);
        back.setContentDescription("return");
        back.setOnClickListener(ignored -> {
            stopPairingServer();
            showPage(Page.STATUS);
        });
        root.addView(back, new LinearLayout.LayoutParams(dp(56), dp(52)));

        TextView title = label("One-time pairing", 30, TEXT, Gravity.START);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title, matchWithTop(8));
        root.addView(description("Connect iPhone and Samsung to the same Wi‑Fi or Samsung hotspot"), matchWithTop(6));

        LinearLayout pairingCard = card(SURFACE, 28);
        pairingCard.setOrientation(LinearLayout.VERTICAL);
        pairingCard.setGravity(Gravity.CENTER_HORIZONTAL);
        pairingCard.setPadding(dp(20), dp(24), dp(20), dp(24));
        pairingCard.addView(label("Pairing code (one-time use)", 14, MUTED, Gravity.CENTER));
        pairingCodeView = label(
                MainScreenPresentation.formatPairingCode(pairingCode), 42, TEXT, Gravity.CENTER);
        pairingCodeView.setTypeface(Typeface.create(Typeface.MONOSPACE, Typeface.BOLD));
        pairingCodeView.setLetterSpacing(0.05f);
        pairingCodeView.setBackground(rounded(Color.rgb(20, 32, 45), 18, BORDER, 1));
        pairingCodeView.setPadding(dp(18), dp(18), dp(18), dp(18));
        pairingCard.addView(pairingCodeView, matchWithTop(18));

        pairingCountdownView = label("Generating security key...", 14, Color.rgb(135, 183, 238), Gravity.CENTER);
        pairingCard.addView(pairingCountdownView, matchWithTop(16));

        ImageView link = icon(android.R.drawable.ic_menu_share, CYAN, 92);
        link.setPadding(dp(22), dp(22), dp(22), dp(22));
        pairingCard.addView(link, new LinearLayout.LayoutParams(dp(112), dp(112)));

        pairingStatus = label("Checking LAN and generating temporary keys...", 15, TEXT, Gravity.CENTER);
        pairingStatus.setMaxLines(4);
        pairingCard.addView(pairingStatus, matchWithTop(10));
        root.addView(pairingCard, matchWithTop(20));

        TextView cancel = secondaryButton("Unpair");
        cancel.setTextColor(DANGER);
        cancel.setOnClickListener(ignored -> {
            stopPairingServer();
            showPage(Page.STATUS);
        });
        root.addView(cancel, matchWithTop(18));

        TextView note = label("Temporary key · Can only be used once", 13, MUTED, Gravity.CENTER);
        note.setCompoundDrawablesWithIntrinsicBounds(android.R.drawable.ic_lock_idle_lock, 0, 0, 0);
        note.setCompoundDrawableTintList(ColorStateList.valueOf(MUTED));
        note.setCompoundDrawablePadding(dp(8));
        root.addView(note, matchWithTop(20));
        return scroll(root);
    }

    private View smsAssistCard() {
        boolean enabled = SmsConfirmationAccessibilityService.isEnabled(this);
        LinearLayout card = card(SURFACE, 20);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(14), dp(16), dp(14));
        LinearLayout header = row();
        header.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout copy = column(0);
        copy.addView(overline("SMS assisted control"));
        copy.addView(label(enabled ? "Enabled · Xiaomi’s sending confirmation pop-up window can be automatically clicked" : "Not turned on · Only affects Xiaomi’s sending confirmation pop-up window",
                13, enabled ? PRIMARY : MUTED, Gravity.START), matchWithTop(3));
        header.addView(copy, weighted());
        card.addView(header);
        card.addView(description("Only click \"Send/Allow\" when SimHelp initiates a system text message and Xiaomi pops up \"Whether to send a text message\". The text message content will not be read or saved."), matchWithTop(6));
        LinearLayout actions = row();
        TextView open = secondaryButton(enabled ? "View assisted control settings" : "Turn on auxiliary control permissions");
        open.setTextColor(PRIMARY);
        open.setOnClickListener(ignored -> {
            try {
                startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
            } catch (RuntimeException error) {
                toast("Unable to open auxiliary control settings, please manually search for \"Accessibility\" in system settings");
            }
        });
        TextView logs = secondaryButton("SMS log");
        logs.setOnClickListener(ignored -> {
            activeDebugFilter = "SMS";
            showPage(Page.DEBUG);
        });
        actions.addView(open, weightedWithEnd(6));
        actions.addView(logs, weightedWithStart(4));
        card.addView(actions, matchWithTop(8));
        boolean notificationAccess = SmsNotificationListenerService.isEnabled(this);
        TextView notification = secondaryButton(notificationAccess
                ? "Reply notification read · Authorized"
                : "Enable reading of reply notifications (recommended by Xiaomi)");
        notification.setTextColor(notificationAccess ? MUTED : PRIMARY);
        notification.setOnClickListener(ignored -> {
            try {
                startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS));
            } catch (RuntimeException error) {
                toast("Unable to open notification read settings, please search for \"Notification usage rights\" in system settings");
            }
        });
        card.addView(notification, matchWithTop(6));
        card.addView(description("Xiaomi restricts non-default SMS apps from reading inbox. After notification reading is turned on, only new text message notifications from com.android.mms will be forwarded to the iPhone; the sending confirmation is still handled by the auxiliary control above."), matchWithTop(4));
        return card;
    }

    private LinearLayout debugFilters() {
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout filterRow = row();
        String[] filters = {"all", "Agent", "SMS", "VoBLE", "VoWLAN", "PCM", "Telecom"};
        for (String filter : filters) {
            boolean selected = filter.equals(activeDebugFilter);
            TextView chip = label(filter, 13, selected ? BG : TEXT, Gravity.CENTER);
            chip.setTypeface(Typeface.DEFAULT, selected ? Typeface.BOLD : Typeface.NORMAL);
            chip.setPadding(dp(16), dp(9), dp(16), dp(9));
            chip.setBackground(rounded(selected ? PRIMARY : SURFACE_HIGH, 18, selected ? PRIMARY : BORDER, 1));
            LinearLayout.LayoutParams chipParams = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            chipParams.rightMargin = dp(8);
            filterRow.addView(chip, chipParams);
            chip.setOnClickListener(ignored -> {
                activeDebugFilter = filter;
                showPage(Page.DEBUG);
            });
        }
        scroll.addView(filterRow);
        LinearLayout holder = column(0);
        holder.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return holder;
    }

    private View modeSelector() {
        selectedMode = selectedMode == null ? AppConfig.mode(this) : selectedMode;
        LinearLayout segment = row();
        segment.setPadding(dp(3), dp(3), dp(3), dp(3));
        segment.setBackground(rounded(SURFACE_HIGH, 24, BORDER, 1));
        segment.addView(segmentItem("remote silence", AppConfig.MODE_REMOTE_SILENT), weighted());
        segment.addView(segmentItem("local display", AppConfig.MODE_LOCAL_AND_PUSH), weighted());
        return segment;
    }

    private TextView segmentItem(String title, String mode) {
        boolean selected = mode.equals(selectedMode);
        TextView item = label(title, 14, selected ? PRIMARY : MUTED, Gravity.CENTER);
        item.setTypeface(Typeface.DEFAULT, selected ? Typeface.BOLD : Typeface.NORMAL);
        item.setPadding(dp(8), dp(12), dp(8), dp(12));
        item.setBackground(rounded(selected ? Color.rgb(19, 70, 61) : Color.TRANSPARENT,
                20, selected ? PRIMARY : Color.TRANSPARENT, 1));
        item.setOnClickListener(ignored -> {
            selectedMode = mode;
            // Persist immediately: previously this only changed a local field and
            // only took effect if the user later found the separate Save button.
            AppConfig.setMode(this, mode);
            if (currentPage == Page.STATUS || currentPage == Page.SETTINGS) showPage(currentPage);
        });
        return item;
    }

    private static final class HealthTile {
        final LinearLayout view;
        final ImageView icon;
        final TextView state;

        HealthTile(LinearLayout view, ImageView icon, TextView state) {
            this.view = view;
            this.icon = icon;
            this.state = state;
        }
    }

    private HealthTile healthTile(String title, String value, int iconResource, boolean healthy) {
        LinearLayout tile = card(SURFACE, 18);
        tile.setOrientation(LinearLayout.HORIZONTAL);
        tile.setGravity(Gravity.CENTER_VERTICAL);
        tile.setPadding(dp(12), dp(15), dp(12), dp(15));
        ImageView icon = icon(iconResource, healthy ? PRIMARY : WARNING, 42);
        icon.setBackground(rounded(healthy ? Color.rgb(17, 66, 57) : Color.rgb(76, 58, 25), 21,
                Color.TRANSPARENT, 0));
        icon.setPadding(dp(10), dp(10), dp(10), dp(10));
        tile.addView(icon, new LinearLayout.LayoutParams(dp(44), dp(44)));
        LinearLayout copy = column(dp(10));
        TextView heading = label(title, 13, TEXT, Gravity.START);
        heading.setSingleLine(true);
        heading.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(heading);
        TextView state = label(value, 13, healthy ? PRIMARY : WARNING, Gravity.START);
        state.setTypeface(Typeface.DEFAULT_BOLD);
        state.setSingleLine(true);
        state.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(state, matchWithTop(4));
        tile.addView(copy, weighted());
        return new HealthTile(tile, icon, state);
    }

    private void renderPCMStatus(boolean running) {
        HealthTile tile = pcmHealthTile;
        if (tile == null || currentPage != Page.STATUS) return;
        int color = running ? PRIMARY : WARNING;
        tile.state.setText(running ? "process running" : "To be started");
        tile.state.setTextColor(color);
        tile.icon.setImageTintList(ColorStateList.valueOf(color));
        tile.icon.setBackground(rounded(running ? Color.rgb(17, 66, 57) : Color.rgb(76, 58, 25),
                21, Color.TRANSPARENT, 0));
    }

    private View audioCompatibilityCard() {
        LinearLayout panel = card(SURFACE, 18);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), dp(14), dp(16), dp(14));
        panel.addView(overline("Agent automatic detection"));
        audioCompatibilityTitle = label("Waiting for audio bridge detection", 17, WARNING, Gravity.START);
        audioCompatibilityTitle.setTypeface(Typeface.DEFAULT_BOLD);
        panel.addView(audioCompatibilityTitle, matchWithTop(8));
        audioCompatibilityDetails = label("", 13, MUTED, Gravity.START);
        audioCompatibilityDetails.setTextIsSelectable(true);
        panel.addView(audioCompatibilityDetails, matchWithTop(8));
        TextView retry = label("Retest", 15, BLUE, Gravity.START | Gravity.CENTER_VERTICAL);
        retry.setMinHeight(dp(48));
        retry.setOnClickListener(ignored -> {
            ShizukuBridgeManager.get(this).refreshBridgeStatus();
            renderAudioCompatibility();
        });
        panel.addView(retry, matchWithTop(4));
        renderAudioCompatibility();
        return panel;
    }

    private void renderAudioCompatibility() {
        if (audioCompatibilityTitle == null || audioCompatibilityDetails == null) return;
        AgentAudioCompatibility.Result result = AgentAudioCompatibility.evaluate(
                ShizukuBridgeManager.get(this).freshAudioHealthReport(),
                "active".equals(CallRepository.diagnosticState()));
        int color = switch (result.level()) {
            case INCOMPATIBLE -> DANGER;
            case OBSERVED -> PRIMARY;
            case ATTENTION -> WARNING;
            case PENDING -> MUTED;
        };
        audioCompatibilityTitle.setText(result.title());
        audioCompatibilityTitle.setTextColor(color);
        if (!result.details().contentEquals(audioCompatibilityDetails.getText())) {
            audioCompatibilityDetails.setText(result.details());
        }
    }

    private LinearLayout pageTitle(String title, String badge) {
        LinearLayout block = column(0);
        TextView heading = label(title, 30, TEXT, Gravity.START);
        heading.setTypeface(Typeface.DEFAULT_BOLD);
        block.addView(heading);
        if (badge != null) {
            TextView chip = label(badge, 13, PRIMARY, Gravity.CENTER);
            chip.setTypeface(Typeface.DEFAULT_BOLD);
            chip.setPadding(dp(12), dp(5), dp(12), dp(5));
            chip.setBackground(rounded(Color.rgb(15, 66, 56), 16, Color.TRANSPARENT, 0));
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            params.topMargin = dp(6);
            block.addView(chip, params);
        }
        return block;
    }

    private void placeSystemCall() {
        String value = number == null ? "" : number.getText().toString().trim();
        if (value.isEmpty()) { toast("Please enter number"); return; }
        if (!dialerRoleHeld()) {
            toast("Please set SimHelp as the default phone app first");
            requestDialerRole();
            return;
        }
        try {
            getSystemService(TelecomManager.class).placeCall(Uri.parse("tel:" + value),
                    DefaultCallAccount.dialExtras(this));
        } catch (RuntimeException error) {
            toast(error.getMessage() == null ? "System dial-up failed" : error.getMessage());
        }
    }

    private void chooseDefaultCallAccount() {
        DefaultCallAccount.Snapshot snapshot = DefaultCallAccount.snapshot(this);
        String[] choices = new String[snapshot.accounts().size() + 1];
        choices[0] = "Follow system default";
        String key = DefaultCallAccount.selectedKey(this);
        int checked = key.isEmpty() ? 0 : -1;
        for (int i = 0; i < snapshot.accounts().size(); i++) {
            DefaultCallAccount.Account account = snapshot.accounts().get(i);
            choices[i + 1] = account.label() + (account.number().isEmpty() ? "" : "\n" + account.number());
            if (key.equals(account.key())) checked = i + 1;
        }
        new AlertDialog.Builder(this).setTitle("Default calling card")
                .setSingleChoiceItems(choices, checked, (dialog, which) -> {
                    if (which == 0) DefaultCallAccount.followSystem(this);
                    else DefaultCallAccount.select(this, snapshot.accounts().get(which - 1));
                    dialog.dismiss();
                    showPage(Page.SETTINGS);
                    toast("Default calling card saved");
                }).setNegativeButton("Cancel", null).show();
    }

    private void continueStartupSetup() {
        if (isFinishing() || isDestroyed() || startupSetupInFlight) return;
        startupSetupPending = true;
        if (!resumed) return;
        if (appUpdates.showStartupNotes(this::continueStartupSetup)) return;
        ShizukuBridgeManager shizuku = ShizukuBridgeManager.get(this);
        ShizukuBridgeManager.StartupSnapshot snapshot = shizuku.startupSnapshot();
        ShizukuStartupPolicy.Prompt prompt = shizukuStartupPolicy.inspect(
                snapshot.installed(), snapshot.running(), snapshot.authorized(), true);
        startupSetupInFlight = true;
        startupSetupPending = false;
        if (prompt != ShizukuStartupPolicy.Prompt.NONE) {
            showShizukuStartupPrompt(prompt);
            return;
        }
        switch (DialerRoleSetupPolicy.initial(
                dialerRoleHeld(), shizuku.dialerRoleAutomationAuthorized())) {
            case COMPLETE -> checkAVFEnvironmentAtStartup();
            case SHIZUKU -> attemptPrivilegedDialerRole(false);
            case SYSTEM_ROLE -> requestDialerRole();
            case SETTINGS -> openDefaultAppsSettings();
        }
    }

    private void scheduleStartupSetup() {
        handler.removeCallbacks(startupSetup);
        handler.postDelayed(startupSetup, 500);
    }

    private void showShizukuStartupPrompt(ShizukuStartupPolicy.Prompt prompt) {
        String title;
        String message;
        String action;
        switch (prompt) {
            case INSTALL -> {
                title = "Requires Shizuku to be installed";
                message = "SimHelp's call audio bridge requires Shizuku. Installation is not currently detected; please start services and authorize SimHelp after installation."
                        + "\\n\\nOfficial download:\\n" + ShizukuBridgeManager.DOWNLOAD_URL;
                action = "Shizuku Shizuku";
            }
            case START -> {
                title = "Shizuku is not running yet";
                message = "Shizuku is installed, but the service has not started yet. Please open Shizuku, use wireless debugging or Root to start the service, and then return to SimHelp."
                        + "\\n\\nCall audio cannot be transferred to iPhone when not ready.";
                action = "Open Shizuku";
            }
            case AUTHORIZE -> {
                title = "Requires Shizuku authorization";
                message = "Shizuku is running but SimHelp is not authorized yet. Please allow SimHelp to use Shizuku to enable call audio bridge."
                        + "\\n\\nIf you have rejected it before, please allow SimHelp in Shizuku's \"Authorized Applications\".";
                action = "Authorize";
            }
            default -> throw new IllegalArgumentException("No Shizuku prompt to present");
        }
        boolean[] awaitingAction = {false};
        shizukuStartupDialog = new AlertDialog.Builder(this).setTitle(title).setMessage(message)
                .setPositiveButton(action, (dialog, which) -> {
                    if (prompt == ShizukuStartupPolicy.Prompt.AUTHORIZE) {
                        awaitingAction[0] = true;
                        attemptPrivilegedDialerRole(true);
                    } else {
                        awaitingAction[0] = openShizukuStartupAction(prompt);
                    }
                })
                .setNegativeButton("later", null).create();
        shizukuStartupDialog.setOnDismissListener(dialog -> {
            shizukuStartupDialog = null;
            if (!awaitingAction[0] && !isFinishing() && !isDestroyed()) {
                startupSetupInFlight = false;
                startupSetupPending = true;
                scheduleStartupSetup();
            }
        });
        shizukuStartupDialog.show();
        if (prompt == ShizukuStartupPolicy.Prompt.INSTALL) {
            TextView text = shizukuStartupDialog.findViewById(android.R.id.message);
            if (text != null) {
                // Selectable URL remains usable even if no browser is installed.
                text.setTextIsSelectable(true);
            }
        }
    }

    private boolean openShizukuStartupAction(ShizukuStartupPolicy.Prompt prompt) {
        try {
            Intent intent = prompt == ShizukuStartupPolicy.Prompt.INSTALL
                    ? new Intent(Intent.ACTION_VIEW, Uri.parse(ShizukuBridgeManager.DOWNLOAD_URL))
                    : getPackageManager().getLaunchIntentForPackage(ShizukuBridgeManager.MANAGER_PACKAGE);
            if (intent == null) {
                toast("Unable to open Shizuku, please install from the official download page");
                return false;
            }
            // Keep the return callback in this Activity's task, even if the
            // package manager's launch intent originally had NEW_TASK set.
            intent.setFlags(intent.getFlags() & ~Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivityForResult(intent, SHIZUKU_SETUP_REQUEST);
            return true;
        } catch (RuntimeException error) {
            BridgeLog.error("shizuku_startup_action_failed", error);
            toast("Unable to open the page, please copy the official download address in the pop-up window");
            return false;
        }
    }

    private void completeStartupSetup() {
        startupSetupInFlight = false;
        startupSetupPending = false;
        startupSetupCompleted = true;
        handler.post(this::maybeShowCrashReportPrompt);
    }

    private void requestDialerRole() {
        RoleManager manager = getSystemService(RoleManager.class);
        if (manager == null || !manager.isRoleAvailable(RoleManager.ROLE_DIALER)) {
            toast("The device does not support the default dialer role");
            continueAfterSystemRoleRequest();
            return;
        }
        try {
            startActivityForResult(manager.createRequestRoleIntent(RoleManager.ROLE_DIALER), ROLE_REQUEST);
        } catch (RuntimeException error) {
            BridgeLog.error("dialer_role_system_request_failed", error);
            continueAfterSystemRoleRequest();
        }
    }

    private void continueAfterSystemRoleRequest() {
        ShizukuBridgeManager shizuku = ShizukuBridgeManager.get(this);
        switch (DialerRoleSetupPolicy.afterSystemRequest(
                dialerRoleHeld(), shizuku.dialerRoleAutomationAvailable())) {
            case COMPLETE -> checkAVFEnvironmentAtStartup();
            case SHIZUKU -> attemptPrivilegedDialerRole(true);
            case SETTINGS -> openDefaultAppsSettings();
            case SYSTEM_ROLE -> requestDialerRole();
        }
    }

    private void attemptPrivilegedDialerRole(boolean requestPermission) {
        ShizukuBridgeManager.get(this).ensureDialerRole(requestPermission, (success, detail) -> {
            if (isFinishing() || isDestroyed()) return;
            refreshStatus();
            DialerRoleSetupPolicy.Action next = DialerRoleSetupPolicy.afterPrivilegedAttempt(
                    success && dialerRoleHeld());
            if (next == DialerRoleSetupPolicy.Action.COMPLETE) {
                toast("The default phone role is enabled by the system");
                checkAVFEnvironmentAtStartup();
            } else {
                toast(detail + ", please select SimHelp in the default app");
                openDefaultAppsSettings();
            }
        });
    }

    private void openDefaultAppsSettings() {
        Intent settings = new Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS);
        try {
            startActivityForResult(settings, DEFAULT_APPS_REQUEST);
        } catch (RuntimeException error) {
            BridgeLog.error("default_apps_settings_open_failed", error);
            Intent details = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + getPackageName()));
            startActivityForResult(details, DEFAULT_APPS_REQUEST);
        }
    }

    private void localCall(String action) {
        if (!dialerRoleHeld()) {
            toast("The current call belongs to another default phone app; please select SimHelp first");
            requestDialerRole();
            return;
        }
        String callId = CallRepository.idForAction(action);
        if (callId.isEmpty()) { toast("There are currently no calls to control"); return; }
        Executors.newSingleThreadExecutor().execute(() -> {
            CallRepository.ActionResult result = CallRepository.execute(
                    MainActivity.this, new AgentCommand(UUID.randomUUID().toString(), action, callId, ""));
            runOnUiThread(() -> toast(result.success ? "Telecom confirmed" : result.error));
        });
    }

    private void refreshAgent() {
        refreshAgent(false);
    }

    private void refreshAgent(boolean showResult) {
        final int generation = ++agentRefreshGeneration;
        agentDetail = "Under detection";
        if (showResult) setAgentRefreshMessage("Requesting" + AppConfig.endpoint(this)
                + "Agent status of…", MUTED);
        updateVisibleStatus();
        Executors.newSingleThreadExecutor().execute(() -> {
            String address = AppConfig.endpoint(this);
            String path = AppConfig.configured(this) ? "/api/android/status" : "/api/health";
            try {
                boolean paired = AppConfig.configured(this);
                AgentClient client = new AgentClient(this);
                String payload = paired ? client.status() : client.health();
                JSONObject result = new JSONObject(payload);
                boolean healthy = result.optBoolean("ok", false);
                String profile = result.optString("runtime_profile", "unknown");
                String detail = paired
                        ? "Interface: GET" + path + " · HTTP 200\nAgent：" + address
                                + "\\nRun mode:" + profile
                                + "· Command to be executed:" + result.optInt("pending_commands", 0)
                                + "\\nRecent activities:" + result.optString("last_seen", "Not recorded")
                        : "Interface: GET" + path + " · HTTP 200\nAgent：" + address
                                + "\\nVersion:" + result.optString("version", "unknown")
                                + "· Operating mode:" + profile
                                + "\\nControl token: not configured yet";
                BridgeLog.info("agent_status_refresh path=" + path + " ok=" + healthy
                        + " profile=" + profile + " endpoint=" + address);
                runOnUiThread(() -> {
                    if (generation != agentRefreshGeneration) return;
                    agentOnline = paired && healthy;
                    agentDetail = healthy
                            ? (paired ? "online" : "Reachable · Control token not yet paired")
                            : "Reachable · Agent reports not ready";
                    if (showResult) setAgentRefreshMessage(
                            (healthy ? "Refresh successful" : "Agent is not ready") + "\n" + detail,
                            healthy ? PRIMARY : WARNING);
                    updateVisibleStatus();
                });
                try {
                    JSONObject pushStatus = new JSONObject(client.pushStatus());
                    runOnUiThread(() -> {
                        if (generation != agentRefreshGeneration) return;
                        updatePushStatus(pushStatus);
                        updateVisibleStatus();
                    });
                } catch (Exception error) {
                    BridgeLog.error("push_status_refresh_failed endpoint=" + address, error);
                    String pushError = error.getClass().getSimpleName() + " · " + error.getMessage();
                    runOnUiThread(() -> {
                        if (generation != agentRefreshGeneration) return;
                        pushConfigured = false;
                        pushDetail = "Status is not readable";
                        cloudRelayConfigured = false;
                        cloudLastError = DebugRedactor.sanitize(pushError);
                        pushDiagnostic = "Failed to read /api/push/status:"
                                + DebugRedactor.sanitize(pushError);
                        updateVisibleStatus();
                    });
                }
            } catch (Exception error) {
                BridgeLog.error("agent_status_refresh_failed path=" + path + " endpoint=" + address, error);
                runOnUiThread(() -> {
                    if (generation != agentRefreshGeneration) return;
                    agentOnline = false;
                    agentDetail = "Offline ·" + error.getClass().getSimpleName();
                    pushConfigured = false;
                    pushDetail = "Agent is unreachable";
                    cloudRelayConfigured = false;
                    cloudLastError = RuntimeMode.agentLabel(this) + "Not reachable";
                    pushDiagnostic = "Restore first" + RuntimeMode.agentLabel(this)
                            + ";Currently unable to query /api/push/status.";
                    if (showResult) setAgentRefreshMessage("Refresh failed · GET" + path
                            + "\nAgent：" + address + "\\nReason:"
                            + DebugRedactor.sanitize(error.getClass().getSimpleName() + " · "
                                    + String.valueOf(error.getMessage())), DANGER);
                    updateVisibleStatus();
                });
            }
        });
    }

    private void setAgentRefreshMessage(String message, int color) {
        agentRefreshMessage = message;
        agentRefreshColor = color;
        if (agentRefreshResult != null) {
            agentRefreshResult.setText(message);
            agentRefreshResult.setTextColor(color);
        }
    }

    private void updatePushStatus(JSONObject result) {
        boolean enabled = result.optBoolean("cloud_enabled", false);
        boolean calls = result.optBoolean("call_push_ready", false);
        boolean messages = result.optBoolean("message_push_ready", false);
        String relay = result.optString("relay_url", "");
        String lastError = result.optString("last_error", "");
        cloudEnabled = enabled;
        cloudRelayConfigured = enabled && result.optBoolean("configured", false) && !relay.isEmpty();
        cloudLastError = DebugRedactor.sanitize(lastError);
        pushConfigured = enabled && calls && messages;
        pushDetail = !enabled ? "The cloud is closed" : pushConfigured ? "Push is configured" : "Incomplete configuration";
        pushDiagnostic = "Cloud switch:" + (enabled ? "turn on" : "closure")
                + "\\nIncoming call Push:" + (calls ? "configured" : "Not ready")
                + "· SMS Push:" + (messages ? "configured" : "Not ready")
                + "\nRelay：" + (relay.isEmpty() ? "Not configured" : relay)
                + "\\nAPNs environment:" + result.optString("environment", "unknown")
                + " · WAN：" + result.optString("wan_interface", "not detected")
                + (lastError.isEmpty() ? "" : "\\nLatest errors:" + DebugRedactor.sanitize(lastError))
                + "\\nNote: Configured does not mean that the public network Relay has been verified to be reachable.";
    }

    private void showFeatureDetails(Feature feature) {
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(featureTitle(feature))
                .setMessage(featureDetails(feature, ""))
                .setPositiveButton("closure", null)
                .setNeutralButton("recheck", (ignored, which) -> showFeatureDetails(feature))
                .create();
        dialog.show();
        if (feature != Feature.AGENT && feature != Feature.PUSH) return;
        Executors.newSingleThreadExecutor().execute(() -> {
            String live;
            try {
                AgentClient client = new AgentClient(this);
                JSONObject result = new JSONObject(feature == Feature.PUSH
                        ? client.pushStatus()
                        : AppConfig.configured(this) ? client.status() : client.health());
                if (feature == Feature.PUSH) {
                    String cloudLogs;
                    try {
                        cloudLogs = cloudAgentLogs(new JSONObject(client.debugSnapshot()));
                    } catch (Exception error) {
                        cloudLogs = "Agent cloud event reading failed:" + DebugRedactor.sanitize(
                                error.getClass().getSimpleName() + " · " + error.getMessage());
                    }
                    String liveCloudLogs = cloudLogs;
                    runOnUiThread(() -> {
                        updatePushStatus(result);
                        updateVisibleStatus();
                        if (dialog.isShowing()) dialog.setMessage(featureDetails(feature,
                                "Real-time query: /api/push/status · HTTP 200\\n\\nAgent cloud events (new to old)\\n"
                                        + liveCloudLogs));
                    });
                    return;
                }
                live = "Real-time query:" + (AppConfig.configured(this) ? "/api/android/status" : "/api/health")
                        + "· HTTP 200\\nReturn: ok=" + result.optBoolean("ok", false)
                        + " · runtime_profile=" + result.optString("runtime_profile", "unknown")
                        + (AppConfig.configured(this)
                            ? " · pending_commands=" + result.optInt("pending_commands", 0)
                            : " · version=" + result.optString("version", "unknown"));
            } catch (Exception error) {
                live = "Real-time query failed:" + DebugRedactor.sanitize(
                        error.getClass().getSimpleName() + " · " + error.getMessage());
                BridgeLog.error("feature_diagnostic_failed feature=" + feature, error);
            }
            String outcome = live;
            runOnUiThread(() -> {
                if (dialog.isShowing()) dialog.setMessage(featureDetails(feature, outcome));
            });
        });
    }

    private String cloudAgentLogs(JSONObject snapshot) {
        JSONArray events = snapshot.optJSONArray("events");
        if (events == null) return "Agent did not return event list";
        StringBuilder output = new StringBuilder();
        int count = 0;
        for (int index = events.length() - 1; index >= 0 && count < 10; index--) {
            JSONObject event = events.optJSONObject(index);
            if (event == null) continue;
            String category = event.optString("category", "");
            if (!category.equals("push") && !category.startsWith("cloud")) continue;
            if (output.length() > 0) output.append('\n');
            output.append(DebugRedactor.sanitize(event.optString("timestamp", "")))
                    .append(" · ").append(category)
                    .append(" · ").append(DebugRedactor.sanitize(event.optString("summary", "")));
            String payload = event.optString("payload", "");
            if (!payload.isEmpty()) output.append("\n  ").append(
                    payload.contains("://") ? "[May contain media credentials, link details omitted]"
                            : DebugRedactor.sanitize(payload));
            count++;
        }
        return output.length() == 0 ? "No Push / Cloud events yet" : output.toString();
    }

    private String featureTitle(Feature feature) {
        return switch (feature) {
            case VOWLAN -> "VoWLAN connection details";
            case AGENT -> RuntimeMode.agentLabel(this) + "Details";
            case PCM -> "PCM Audio Bridge Details";
            case PUSH -> "Push / Relay details";
            case SHIZUKU -> "Permission channel details";
        };
    }

    private String featureDetails(Feature feature, String live) {
        String log = BridgeLog.read();
        String latestVoWLAN = MainScreenPresentation.latestContaining(log, "vowlan_state");
        String currentVoWLAN = VoWLANGatewayService.currentDiagnosticState();
        String details;
        String[] keywords;
        switch (feature) {
            case VOWLAN -> {
                boolean paired = VoWLANPairingStore.configured(this);
                String address = localVoWLANAddress();
                String pcmBackend = RuntimeMode.isStandalone(this) ? "Native PCM port 7580" : "AVF PCM port 7580";
                String reason = !paired ? "Not paired with iPhone yet"
                        : address.isEmpty() ? "No same-network Wi-Fi or Samsung hotspot address available"
                        : currentVoWLAN.contains("avf=missing") ? "AVF virtual network card does not appear"
                        : currentVoWLAN.contains("agent_ready=false") ? "Agent failed VoWLAN readiness check"
                        : currentVoWLAN.contains("pcm_ready=false") ? pcmBackend + "Not ready"
                        : !vowlanReady() ? "The VoWLAN service has not completed the current check:" + currentVoWLAN
                        : "The current check items are met; actual call verification is still required";
                details = "pair:" + (paired ? "Key saved" : "Not paired")
                        + "\\nLocal area network:" + (address.isEmpty() ? "not found" : address)
                        + "\\nStatus reason:" + reason
                        + "\\nCurrent check:" + currentVoWLAN
                        + "\\nLatest checks:" + (latestVoWLAN.isEmpty() ? "none" : latestVoWLAN);
                keywords = new String[]{"vowlan", "pairing"};
            }
            case AGENT -> {
                boolean standalone = RuntimeMode.isStandalone(this);
                details = "state:" + agentDetail
                        + (standalone ? "\\nRun location: this APK front-end service"
                                : "\\nAddress:" + AppConfig.endpoint(this)
                                + "\\nControl token:" + (AppConfig.configured(this) ? "configured" : "Not configured"))
                        + "\\nReason:" + (agentOnline ? "The latest status check passed"
                            : standalone ? "Check foreground services, notification permissions and system power saving restrictions"
                            : "Check that AVF Linux is running, that the address is :8575, and that the control token matches")
                        + "\n" + agentRefreshMessage;
                keywords = new String[]{"agent", "watchdog", "http_request", "avf"};
            }
            case PCM -> {
                String shizuku = ShizukuBridgeManager.get(this).status();
                String pcmBackend = RuntimeMode.isStandalone(this) ? "Native PCM port 7580" : "AVF PCM port 7580";
                String reason = !privilegeReady() ? "Root/Shizuku authority channel is not connected yet, PCM user service is unavailable"
                        : currentVoWLAN.contains("pcm_ready=false") ? pcmBackend + "Not responding"
                        : !pcmBridgeRunning() ? "The PCM audio bridge process is not running yet"
                        : "The current check items are met; the actual call still needs to be verified for two-way audio";
                details = "Permission channel:" + shizuku + "\\nBridge status:" + (pcmBridgeRunning() ? "Running" : "To be started")
                        + "\\nStatus reason:" + reason
                        + "\\nCurrent VoWLAN check:" + currentVoWLAN
                        + "\\nLatest VoWLAN check:" + (latestVoWLAN.isEmpty() ? "none" : latestVoWLAN);
                keywords = new String[]{"pcm", "shizuku", "vowlan_state"};
            }
            case PUSH -> {
                details = "state:" + pushDetail + "\n" + pushDiagnostic
                        + "\\nReason:" + (agentOnline ? "Please check switches, relay addresses, APNs tokens and recent errors"
                            : "Unable to confirm cloud registration or heartbeat when Agent is unreachable");
                keywords = new String[]{"push", "relay", "pairing"};
            }
            case SHIZUKU -> {
                String shizuku = ShizukuBridgeManager.get(this).status();
                details = "state:" + shizuku + "\\nReason:" + (privilegeReady()
                        ? "The permission channel is connected; only one Root and Shizuku are needed. Whether there is sound still needs to verify the PCM routing."
                        : "Check selected Root / Shizuku authorization and PCM user services; start timeout to manually retry or switch channels");
                keywords = new String[]{"shizuku", "local_output"};
            }
            default -> throw new IllegalStateException("unknown function");
        }
        String recent = MainScreenPresentation.recentMatchingLogLines(log, 12, keywords);
        return details + (live.isEmpty() ? "" : "\n\n" + live)
                + "\\n\\nRelated logs (newest to oldest)\\n" + recent;
    }

	private void checkAVFEnvironmentAtStartup() {
		if (RuntimeMode.isStandalone(this)) {
			StandaloneAgentService.start(this);
			completeStartupSetup();
			return;
		}
		if (avfStartupPromptShown) { completeStartupSetup(); return; }
		AVFEnvironmentDetector.Snapshot snapshot = AVFEnvironmentDetector.inspect(this);
		boolean agentConfigured = AppConfig.configured(this);
		if (!AVFStartupPolicy.shouldPrompt(snapshot.state(), agentConfigured)) {
            completeStartupSetup();
            return;
        }
		avfStartupPromptShown = true;
		boolean needsInstall = snapshot.state() == AVFStartupPolicy.State.RUNNING && !agentConfigured;
		boolean canLaunch = snapshot.state() == AVFStartupPolicy.State.READY_TO_START;
		AlertDialog dialog = new AlertDialog.Builder(this)
				.setTitle(needsInstall ? "Configure SimHelp AVF Agent" : "Need to start AVF Linux environment")
				.setMessage(avfEnvironmentSummary(snapshot)
						+ (needsInstall
						? "\\n\\nIf it has not been installed yet, copy the first installation command to Linux Terminal;" +
								"If the Agent is already running, first execute sudo simhelp-avf-pair pairing and check installerd."
						: "\\n\\nAfter starting Linux, paste the SimHelp one-click installation command in Terminal."))
				.setPositiveButton(needsInstall ? "Copy the first installation command"
						: canLaunch ? "Start Linux Terminal" : "Open developer options",
						(ignored, which) -> {
							if (needsInstall) copyAVFInstallCommand();
							else if (canLaunch) openAVFTerminalOrSettings();
							else AVFEnvironmentActions.openDeveloperOptions(this);
						})
				.setNeutralButton(needsInstall ? "Open Linux Terminal" : "Copy the installation command",
						(ignored, which) -> {
							if (needsInstall) openAVFTerminalOrSettings();
							else copyAVFInstallCommand();
						})
				.setNegativeButton("later", null)
				.create();
		dialog.setOnDismissListener(ignored -> completeStartupSetup());
		dialog.show();
	}

	private String avfEnvironmentSummary(AVFEnvironmentDetector.Snapshot snapshot) {
		return switch (snapshot.state()) {
			case RUNNING -> "AVF Linux is started and can connect to the Agent.";
			case READY_TO_START -> "AVF and Linux Terminal are provided on the system, but virtual Linux has not been started yet.";
			case TERMINAL_DISABLED -> "The system includes Linux Terminal, but it is currently disabled by developer options.";
			case TERMINAL_MISSING -> snapshot.restrictedChinaOEM()
					? "Currently, domestic ROMs do not provide the AOSP Linux Terminal component; SimHelp cannot be forcibly reinstalled or opened with ordinary application permissions."
					: "The system declares support for AVF, but the AOSP Linux Terminal component is not installed.";
			case AVF_UNSUPPORTED -> snapshot.restrictedChinaOEM()
					? "Currently, domestic ROMs do not expose AVF Linux capabilities to third-party applications and cannot be forcibly turned on by SimHelp."
					: "The current system does not expose AVF capabilities, please check the system version and manufacturer support.";
		};
	}

	private void openAVFTerminalOrSettings() {
		if (!AVFEnvironmentActions.openTerminal(this)) {
			AVFEnvironmentActions.openDeveloperOptions(this);
			toast("Bootable Linux Terminal not found, please enable it in developer options");
		}
	}

	private void copyAVFInstallCommand() {
		getSystemService(ClipboardManager.class).setPrimaryClip(
				ClipData.newPlainText("SimHelp AVF one-click installation", AVFStartupPolicy.installCommand()));
		toast("AVF one-click installation command has been copied");
	}

	private void refreshInstallerStatus() {
		if (installerStatus == null) return;
		if (!AppConfig.configured(this)) {
			installerStatus.setText("The control token has not been paired yet. First complete the first signature installation in AVF Linux Terminal," +
					"Then run sudo simhelp-avf-pair and save the token to the configuration above." +
					"If there is an Agent but the installation service is unavailable, first check the airsim-installerd service in Terminal and do not clear the Linux data.");
			return;
		}
		Executors.newSingleThreadExecutor().execute(() -> {
			try {
				String value = new AgentReleaseManager(this).status();
				runOnUiThread(() -> {
					if (installerStatus != null) installerStatus.setText("installerd online\\n" + value);
				});
			} catch (Exception error) {
				runOnUiThread(() -> {
					if (installerStatus != null) installerStatus.setText("installerd is not available ·" +
							error.getClass().getSimpleName() +
							". Please check sudo systemctl status airsim-installerd in Linux Terminal;" +
							"Do not clear Linux data.");
				});
			}
		});
	}

	private void runAgentMaintenance(String action) {
		if (!AppConfig.configured(this)) {
			if (installerStatus != null) installerStatus.setText(
					"Not paired yet. First complete the first installation of AVF Linux and run sudo simhelp-avf-pair," +
					"Save the control token before updating, repairing, or rolling back.");
			return;
		}
		if (installerStatus != null) installerStatus.setText("Agent operation in progress ·" + action);
		Executors.newSingleThreadExecutor().execute(() -> {
			try {
				AgentReleaseManager manager = new AgentReleaseManager(this);
				String result = switch (action) {
					case "repair" -> manager.repairLatest();
					case "rollback" -> manager.rollback();
					default -> manager.installLatest();
				};
				runOnUiThread(() -> {
					if (installerStatus != null) installerStatus.setText("Agent operation completed\\n" + result);
					toast("AVF Agent operation completed");
					refreshAgent();
				});
			} catch (Exception error) {
				BridgeLog.error("avf_agent_maintenance_failed action=" + action, error);
				runOnUiThread(() -> {
					if (installerStatus != null) installerStatus.setText("Agent operation failed ·" + error.getMessage());
					toast("AVF Agent operation failed");
				});
			}
		});
	}

    private void updateVisibleStatus() {
        if (status != null) status.setText(roleText() + "\nAgent：" + agentDetail);
        if (currentPage == Page.STATUS && contentHost != null
                && bottomBar.getVisibility() == View.VISIBLE) showPage(Page.STATUS);
    }

    private void startPairing() {
        stopPairingServer();
        if (pairingStatus != null) pairingStatus.setText("Checking LAN and generating temporary keys...");
        pairingServer = new PairingServer(this, new PairingServer.Listener() {
            @Override public void onStarted(String code, String address, long expiresAtMillis) {
                BridgeLog.info("pairing_started address=" + address + " expires_at=" + expiresAtMillis);
                pairingCode = code;
                pairingExpiresAt = expiresAtMillis;
                runOnUiThread(() -> {
                    if (pairingCodeView != null) pairingCodeView.setText(
                            MainScreenPresentation.formatPairingCode(code));
                    if (pairingStatus != null) {
                        pairingStatus.setText("Wait for iPhone auto-discovery or manual address pairing...\\n" + address);
                        pairingStatus.setTextIsSelectable(true);
                    }
                    startPairingCountdown();
                });
            }

            @Override public void onSucceeded(String agentResponse) {
                BridgeLog.info("pairing_completed");
                boolean localMode = false;
                try {
                    localMode = new JSONObject(agentResponse).optBoolean("local_mode", false);
                } catch (Exception ignored) {
                    // Older Agent responses do not carry a mode marker.
                }
                boolean pairedLocally = localMode;
                runOnUiThread(() -> {
                    cancelPairingCountdown();
                    if (pairingCodeView != null) {
                        pairingCodeView.setText("Pairing successful");
                        pairingCodeView.setTextSize(28);
                    }
                    if (pairingCountdownView != null) pairingCountdownView.setText("VoWLAN keys saved safely");
                    if (pairingStatus != null) pairingStatus.setText(pairedLocally
                            ? "Local mode is enabled and does not use Relay or Push"
                            : "iOS Push identity written to Android Agent");
                    refreshAgent();
                });
            }

            @Override public void onFailed(String message) {
                BridgeLog.error("pairing_failed", new IllegalStateException(message));
                runOnUiThread(() -> {
                    cancelPairingCountdown();
                    if (pairingCountdownView != null) pairingCountdownView.setText("Pairing window closed");
                    if (pairingStatus != null) pairingStatus.setText("Pairing failed:" + message);
                });
            }
        });
        pairingServer.start();
    }

    private void startPairingCountdown() {
        cancelPairingCountdown();
        long remaining = Math.max(0, pairingExpiresAt - System.currentTimeMillis());
        pairingCountdown = new CountDownTimer(remaining, 1_000) {
            @Override public void onTick(long millisUntilFinished) {
                long seconds = millisUntilFinished / 1_000;
                if (pairingCountdownView != null) pairingCountdownView.setText(
                        String.format(java.util.Locale.CHINA, "%02d: Invalid after %02d", seconds / 60, seconds % 60));
            }

            @Override public void onFinish() {
                if (pairingCountdownView != null) pairingCountdownView.setText("Pairing window has expired");
            }
        }.start();
    }

    private void cancelPairingCountdown() {
        if (pairingCountdown != null) pairingCountdown.cancel();
        pairingCountdown = null;
    }

    private void stopPairingServer() {
        cancelPairingCountdown();
        PairingServer active = pairingServer;
        pairingServer = null;
        if (active != null) {
            try { active.close(); }
            catch (Exception error) { BridgeLog.error("pairing_close", error); }
        }
    }

    private void refreshStatus() {
        refreshShizukuStatus();
    }

    private EditText portField(String hint, int value) {
        EditText input = new EditText(this);
        input.setText(value <= 0 && hint.contains("0 = automatic") ? "0" : Integer.toString(value));
        input.setHint(hint);
        input.setTextColor(TEXT);
        input.setHintTextColor(MUTED);
        input.setInputType(InputType.TYPE_CLASS_NUMBER);
        return input;
    }

    /** Returns the port, or -1 when the text is not a usable port. */
    private static int parsePort(EditText input, int fallback) {
        String text = input.getText().toString().trim();
        if (text.isEmpty()) return fallback;
        if (text.length() > 5 || !text.chars().allMatch(Character::isDigit)) return -1;
        int value = Integer.parseInt(text);
        return NetworkSettings.isUsablePort(value) ? value : -1;
    }

    private void refreshShizukuStatus() {
        if (shizukuStatus != null) shizukuStatus.setText(ShizukuBridgeManager.get(this).status());
        if (privilegeChannelGroup == null) return;
        PrivilegeChannelPreference.Channel selected = PrivilegeChannelPreference.get(this);
        for (java.util.Map.Entry<Integer, PrivilegeChannelPreference.Channel> entry
                : privilegeChannelIDs.entrySet()) {
            if (entry.getValue() != selected) continue;
            int id = entry.getKey();
            if (privilegeChannelGroup.getCheckedRadioButtonId() != id) {
                updatingPrivilegeChannel = true;
                privilegeChannelGroup.check(id);
                updatingPrivilegeChannel = false;
            }
            return;
        }
    }

    private void refreshDebugLog() {
        if (debugRows == null) return;
        String log = BridgeLog.read();
        if (log.equals(lastRenderedDebugLog) && activeDebugFilter.equals(lastRenderedDebugFilter)) return;
        lastRenderedDebugLog = log;
        lastRenderedDebugFilter = activeDebugFilter;
        debugRows.removeAllViews();
        String visible = MainScreenPresentation.recentLogLines(
                log, activeDebugFilter, 60);
        if (visible.startsWith("None yet") || visible.startsWith("This category")) {
            TextView empty = description(visible);
            empty.setGravity(Gravity.CENTER);
            empty.setPadding(dp(8), dp(28), dp(8), dp(28));
            debugRows.addView(empty);
            return;
        }
        String[] lines = visible.split("\\R");
        for (int index = 0; index < lines.length; index++) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.TOP);
            row.setPadding(dp(2), dp(6), dp(2), dp(6));

            View dot = new View(this);
            dot.setBackground(rounded(MainScreenPresentation.isErrorLog(lines[index]) ? DANGER : PRIMARY,
                    4, Color.TRANSPARENT, 0));
            LinearLayout.LayoutParams dotParams = new LinearLayout.LayoutParams(dp(7), dp(7));
            dotParams.topMargin = dp(5);
            row.addView(dot, dotParams);

            LinearLayout copy = column(dp(9));
            TextView metadata = label(MainScreenPresentation.logMetadata(lines[index]),
                    10, MUTED, Gravity.START);
            copy.addView(metadata);
            TextView title = label(MainScreenPresentation.activitySummary(lines[index]),
                    13, TEXT, Gravity.START);
            title.setTypeface(Typeface.DEFAULT_BOLD);
            copy.addView(title, matchWithTop(1));
            TextView detail = label(MainScreenPresentation.eventBody(lines[index]),
                    11, MUTED, Gravity.START);
            detail.setTypeface(Typeface.MONOSPACE);
            copy.addView(detail, matchWithTop(1));
            row.addView(copy, weighted());
            debugRows.addView(row);

            if (index < lines.length - 1) {
                View divider = new View(this);
                divider.setBackgroundColor(BORDER);
                LinearLayout.LayoutParams dividerParams = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, dp(1));
                dividerParams.leftMargin = dp(18);
                debugRows.addView(divider, dividerParams);
            }
        }
    }

    private void copyDebugLog() {
        String value = BridgeLog.read();
        getSystemService(ClipboardManager.class).setPrimaryClip(
                ClipData.newPlainText("SimHelp Debug Log", value));
        toast("Log copied");
    }

    private void exportDebugLog() {
        Intent share = new Intent(Intent.ACTION_SEND);
        share.setType("text/plain");
        share.putExtra(Intent.EXTRA_SUBJECT, "SimHelp Android Diagnostics");
        share.putExtra(Intent.EXTRA_TEXT, BridgeLog.read());
        startActivity(Intent.createChooser(share, "Export diagnostics"));
    }

	private void shareCrashReport() {
		String payload = CrashReportSharePayload.compose(
				CrashReportStore.read(getFilesDir()), BridgeLog.read());
		if (payload.isBlank()) {
			toast("No crash report yet");
			return;
		}
		Intent share = new Intent(Intent.ACTION_SEND);
		share.setType("text/plain");
		share.putExtra(Intent.EXTRA_SUBJECT, "SimHelp Android crash report");
		share.putExtra(Intent.EXTRA_TEXT, payload);
		startActivity(Intent.createChooser(share, "Send crash report"));
	}

	private void maybeShowCrashReportPrompt() {
		if (!resumed || startupSetupInFlight || isFinishing() || isDestroyed()) return;
        if (crashPromptShown || !CrashReportStore.hasReport(getFilesDir())) {
            appUpdates.foreground();
            return;
        }
		crashPromptShown = true;
		new AlertDialog.Builder(this)
				.setTitle("Last crash detected")
				.setMessage("SimHelp has saved the desensitization report locally. It will not be uploaded automatically. Do you want to send it to the developer now?")
				.setPositiveButton("send", (ignored, which) -> shareCrashReport())
				.setNeutralButton("Check", (ignored, which) -> showPage(Page.DEBUG))
				.setNegativeButton("later", null)
				.setOnDismissListener(ignored -> appUpdates.foreground())
				.show();
	}

    private void saveConfiguration() {
        try {
            if (RuntimeMode.isStandalone(this)) {
                AppConfig.save(this, "", "", selectedMode);
            } else {
                AppConfig.save(this, endpoint.getText().toString(), token.getText().toString(), selectedMode);
            }
            AgentWatchdogService.start(this);
            toast(RuntimeMode.isStandalone(this)
                    ? "Pattern saved, built-in Agent starting" : "The configuration has been saved and the daemon service is starting");
            refreshAgent();
        } catch (IllegalArgumentException error) {
            toast(error.getMessage());
        }
    }

    private String roleText() {
        return "Default phone role:" + (dialerRoleHeld() ? "Enabled" : "Not enabled");
    }

    private boolean dialerRoleHeld() {
        RoleManager manager = getSystemService(RoleManager.class);
        return manager != null && manager.isRoleAvailable(RoleManager.ROLE_DIALER)
                && manager.isRoleHeld(RoleManager.ROLE_DIALER);
    }

    private String vowlanNetworkLine() {
        String host = localVoWLANAddress();
        return host.isEmpty() ? "Same Wi‑Fi / Samsung Hotspot" : "Same Wi-Fi ·" + host;
    }

    private boolean vowlanReady() {
        String state = VoWLANGatewayService.currentDiagnosticState();
        return dialerRoleHeld() && VoWLANPairingStore.configured(this) && !localVoWLANAddress().isEmpty()
                && state.contains("paired=true") && state.contains("agent_ready=true")
                && state.contains("pcm_ready=true") && state.contains("dialer_role=true")
                && !state.contains("avf=missing");
    }

    private String localVoWLANAddress() {
        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces.hasMoreElements()) {
                NetworkInterface item = interfaces.nextElement();
                if (!item.isUp() || item.isLoopback()) continue;
                Enumeration<InetAddress> addresses = item.getInetAddresses();
                while (addresses.hasMoreElements()) {
                    InetAddress address = addresses.nextElement();
                    if (address instanceof Inet4Address
                            && VoWLANNetworkPolicy.isVoWLANInterface(item.getName(), address.getHostAddress())) {
                        return address.getHostAddress();
                    }
                }
            }
        } catch (Exception ignored) {}
        return "";
    }

    private void refreshPrivilegeTile() {
        if (privilegeHealthTile == null) return;
        ShizukuBridgeManager manager = ShizukuBridgeManager.get(this);
        boolean ready = manager.privilegeConnected();
        privilegeHealthTile.state.setText(ready ? manager.activePrivilegeLabel() + "Connected" : "To be connected");
        privilegeHealthTile.state.setTextColor(ready ? PRIMARY : WARNING);
        privilegeHealthTile.icon.setImageTintList(ColorStateList.valueOf(ready ? PRIMARY : WARNING));
    }

    private boolean privilegeReady() {
        return ShizukuBridgeManager.get(this).privilegeConnected();
    }

    private boolean pcmBridgeRunning() {
        return ShizukuBridgeManager.get(this).bridgeRunning();
    }

    private String latestActivity() {
        String line = MainScreenPresentation.recentLogLines(BridgeLog.read(), "", 1);
        return "No Debug log yet".equals(line)
                ? "Waiting for connection activity"
                : "just ·" + MainScreenPresentation.activitySummary(line);
    }

    private LinearLayout pageRoot() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(20), dp(18), dp(30));
        root.setBackgroundColor(BG);
        return root;
    }

    private ScrollView scroll(View content) {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        scroll.addView(content, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return scroll;
    }

    private LinearLayout card(int color, int radius) {
        LinearLayout card = new LinearLayout(this);
        card.setBackground(rounded(color, radius, BORDER, 1));
        return card;
    }

    private LinearLayout row() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        return row;
    }

    private LinearLayout column(int startPadding) {
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        if (startPadding > 0) column.setPadding(startPadding, 0, 0, 0);
        return column;
    }

    private TextView sectionTitle(String value) {
        TextView title = label(value, 18, TEXT, Gravity.START);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        return title;
    }

    private TextView overline(String value) {
        TextView text = label(value, 12, MUTED, Gravity.START);
        text.setLetterSpacing(0.04f);
        return text;
    }

    private TextView description(String value) {
        TextView text = label(value, 13, MUTED, Gravity.START);
        text.setLineSpacing(dp(2), 1f);
        return text;
    }

    private TextView label(String value, int sp, int color, int gravity) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        view.setGravity(gravity);
        view.setFontFeatureSettings("kern");
        return view;
    }

    private EditText input(String hint, int type) {
        EditText view = new EditText(this);
        view.setHint(hint);
        view.setHintTextColor(MUTED);
        view.setTextColor(TEXT);
        view.setTextSize(15);
        view.setInputType(type);
        view.setSingleLine(true);
        view.setPadding(dp(14), dp(11), dp(14), dp(11));
        view.setBackground(rounded(SURFACE_HIGH, 15, BORDER, 1));
        return view;
    }

    private TextView primaryButton(String title, int color) {
        TextView button = label(title, 16, Color.WHITE, Gravity.CENTER);
        button.setTypeface(Typeface.DEFAULT_BOLD);
        button.setMinHeight(dp(54));
        button.setPadding(dp(16), dp(13), dp(16), dp(13));
        button.setBackground(rounded(color, 20, color, 1));
        button.setClickable(true);
        button.setFocusable(true);
        return button;
    }

    private TextView secondaryButton(String title) {
        TextView button = label(title, 14, TEXT, Gravity.CENTER);
        button.setTypeface(Typeface.DEFAULT_BOLD);
        button.setMinHeight(dp(50));
        button.setPadding(dp(12), dp(12), dp(12), dp(12));
        button.setBackground(rounded(SURFACE_HIGH, 18, BORDER, 1));
        button.setClickable(true);
        button.setFocusable(true);
        return button;
    }

    private ImageView icon(int resource, int tint, int contentSize) {
        ImageView view = new ImageView(this);
        view.setImageResource(resource);
        view.setImageTintList(ColorStateList.valueOf(tint));
        view.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        view.setMinimumWidth(dp(contentSize));
        view.setMinimumHeight(dp(contentSize));
        return view;
    }

    private GradientDrawable rounded(int color, int radius, int strokeColor, int strokeWidth) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radius));
        if (strokeWidth > 0 && strokeColor != Color.TRANSPARENT) {
            drawable.setStroke(dp(strokeWidth), strokeColor);
        }
        return drawable;
    }

    private LinearLayout.LayoutParams weighted() {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
    }

    private LinearLayout.LayoutParams weightedWithStart(int start) {
        LinearLayout.LayoutParams params = weighted();
        params.leftMargin = dp(start);
        return params;
    }

    private LinearLayout.LayoutParams weightedWithEnd(int end) {
        LinearLayout.LayoutParams params = weighted();
        params.rightMargin = dp(end);
        return params;
    }

    private LinearLayout.LayoutParams matchWithTop(int top) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.topMargin = dp(top);
        return params;
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show();
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == DIAGNOSTIC_TXT_REQUEST) {
            if (result == RESULT_OK && data != null && data.getData() != null) {
                Uri destination = data.getData();
                DIAGNOSTIC_WORKER.execute(() -> {
                    try (java.io.OutputStream output = getContentResolver().openOutputStream(destination, "wt")) {
                        if (output == null) throw new java.io.IOException("document unavailable");
                        String report = AudioWatchdogReport.compose(AppInformation.version(this), Build.VERSION.SDK_INT,
                                Build.MANUFACTURER, Build.MODEL, BridgeLog.read());
                        output.write(report.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                        runOnUiThread(() -> toast("Watchdog TXT saved"));
                    } catch (Exception error) {
                        runOnUiThread(() -> toast("Failed to save TXT, please try again or use copy log"));
                    }
                });
            }
            return;
        }
        refreshStatus();
        if (request == ROLE_REQUEST) {
            continueAfterSystemRoleRequest();
        } else if (request == DEFAULT_APPS_REQUEST) {
            if (dialerRoleHeld()) checkAVFEnvironmentAtStartup();
            else {
                toast("SimHelp still doesn't get default phone role");
                completeStartupSetup();
            }
        } else if (request == SHIZUKU_SETUP_REQUEST) {
            startupSetupInFlight = false;
            startupSetupPending = true;
            scheduleStartupSetup();
        }
    }

    @Override protected void onResume() {
        super.onResume();
        resumed = true;
        if (hasVoBLEPermissions()) {
            com.simhelp.phonecontrol.voble.VoBLEGatewayService.start(this);
        }
        if (startupSetupPending) scheduleStartupSetup();
        if (currentPage == Page.SETTINGS && !voBLEAuthenticationVisible) showPage(Page.SETTINGS);
        if ((currentPage == Page.STATUS || currentPage == Page.SETTINGS) && pcmStatusPoller != null) pcmStatusPoller.start();
        if (voBLEAuthenticationVisible) handler.post(voBLEAuthenticationRefresh);
        refreshShizukuStatus();
		startSMSInboxBaselineIfAuthorized();
        if (startupSetupCompleted && !startupSetupPending && !startupSetupInFlight) {
            handler.post(this::maybeShowCrashReportPrompt);
        }
    }

    @Override protected void onPause() {
        resumed = false;
        if (appUpdates != null) appUpdates.pause();
        if (pcmStatusPoller != null) pcmStatusPoller.stop();
        handler.removeCallbacks(voBLEAuthenticationRefresh);
        super.onPause();
    }

    @Override public void onBackPressed() {
        if (bottomBar != null && bottomBar.getVisibility() == View.GONE) {
            stopPairingServer();
            showPage(Page.STATUS);
            return;
        }
        if (currentPage != Page.STATUS) {
            showPage(Page.STATUS);
            return;
        }
        super.onBackPressed();
    }

    @Override protected void onDestroy() {
        if (appUpdates != null) appUpdates.destroy();
        handler.removeCallbacks(startupSetup);
        if (shizukuStartupDialog != null) {
            shizukuStartupDialog.setOnDismissListener(null);
            shizukuStartupDialog.dismiss();
        }
        if (pcmStatusPoller != null) pcmStatusPoller.stop();
        handler.removeCallbacks(debugRefresh);
        handler.removeCallbacks(voBLEAuthenticationRefresh);
        stopPairingServer();
        super.onDestroy();
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putBoolean(SHIZUKU_STARTUP_CHECKED, shizukuStartupPolicy.checked());
        super.onSaveInstanceState(outState);
    }
}
