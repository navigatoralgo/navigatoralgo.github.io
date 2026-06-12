//+------------------------------------------------------------------+
//|                                         TradeCopierUltimate.mq5  |
//|                   Copyright 2024-2026 Navigator Trading Systems  |
//|                    All-in-One Trade Copier with Telegram         |
//+------------------------------------------------------------------+
#property copyright "Navigator Trading Systems"
#property link      "https://www.mql5.com/en/users/janithasandu"
#property version   "7.10"
#property description "TRADE COPIER ULTIMATE v7.10 - ALL-IN-ONE"
#property description "3 Signal Modes: Bridge + Bot API + Manual File"
#property description "Plus: Local Trade Copier + Telegram Broadcaster"
#property description "Sub-Second Copy Speed | Non-Blocking | Multi-TP"

#include <Trade\Trade.mqh>
#include <Canvas/Canvas.mqh>

#define TCU_VERSION_STR "v7.10"

//--- Enums
enum ENUM_COPIER_MODE { MODE_DISABLED, MODE_MASTER, MODE_SLAVE };
enum ENUM_LOT_MODE { LOT_FIXED, LOT_LEGACY_UNUSED, LOT_RISK_PERCENT };
enum ENUM_COPIER_LOT_MODE { COPIER_LOT_COPY_MASTER, COPIER_LOT_FIXED, COPIER_LOT_MULTIPLIER, COPIER_LOT_RISK_PCT, COPIER_LOT_BALANCE_PROPORTIONAL };
enum ENUM_PANEL_MODE { PANEL_FULL, PANEL_COMPACT };
enum ENUM_OPPOSITE_ACTION { OPP_NOTHING, OPP_CLOSE_OPPOSITE, OPP_CLOSE_ALL };
enum ENUM_SLIPPAGE_ACTION { SLIP_SKIP_SIGNAL, SLIP_OPEN_PENDING };
enum ENUM_TRADE_COMMENT_MODE { TRADE_COMMENT_DEFAULT, TRADE_COMMENT_OFF, TRADE_COMMENT_CUSTOM };
enum ENUM_STARTUP_COPY_MODE { COPY_NEW_TRADES_ONLY, COPY_ALL_EXISTING_TRADES };

// [v6.01 FIX] Daily-loss boundary timezone. Prop firms reset P/L at a SPECIFIC
// wall-clock moment which often differs from the broker's server clock (broker
// servers are usually GMT+2/+3). Picking the wrong boundary is the #1 reason
// EAs fail prop firm challenges -- you think it's a fresh day, the prop firm
// disagrees, you blow the daily limit while the kill switch sits idle.
enum ENUM_DAILY_RESET_TZ {
   DAILY_TZ_BROKER = 0,   // Use broker server time (legacy default)
   DAILY_TZ_UTC    = 1    // Use UTC midnight (most prop firms)
};

//--- Input Parameters -- QUICK START settings come first!

enum ENUM_PARTIAL_MODE {
   PARTIAL_PERCENTAGE=0,  // Use % of position
   PARTIAL_FIXED_LOTS=1   // Use fixed lots
};

enum ENUM_PARTIAL_SCOPE {
   PARTIAL_SCOPE_AUTO=0,  // Ignore signal Multi-TP split trades
   PARTIAL_SCOPE_ALL=1    // Apply to all tracked trades
};

input group ">>> QUICK START (CONFIGURE THESE) <<<";
input bool     inp_EnableBotAPIMode      = false;               // Step 1: Enable Telegram Bot API mode
input string   inp_TelegramBotToken      = "";                  // Step 2: Paste your Bot Token from @BotFather
input string   inp_TelegramChatID        = "";                  // Step 3: Your Chat ID (use @userinfobot)

input group "=== SIGNAL INGESTION (Advanced) ===";
input int      inp_TelegramPollSeconds   = 3;                   // Bot API poll interval (seconds)
input group " ";
input group "--- Bridge App ---";
input bool     inp_EnableBridgeMode      = false;               // Advanced: Use Bridge app for private channels
input int      inp_BridgePort            = 5555;                // Bridge HTTP port
input int      inp_BridgePollMs          = 1000;                // Bridge poll interval (ms)
input string   inp_AllowedBridgeSources  = "";                  // Legacy unused (bridge now handles per-account group routing)
input group " ";
input group "--- Discord ---";
input bool     inp_EnableDiscordMode     = false;               // Enable Discord webhook sending
input string   inp_DiscordWebhookURL     = "";                  // Discord webhook URL for alerts/broadcasts
input int      inp_DiscordPollSeconds    = 5;                   // Legacy unused (kept for backward compatibility)

input group "--- Advanced: EA-to-EA Copier ---";
input ENUM_COPIER_MODE inp_CopierMode       = MODE_DISABLED;        // Local EA-to-EA Copier
input string   inp_CopierFileName           = "TradeCopier.csv";
input bool     inp_CopierAutoClose          = true;                 // Auto-close slave when master closes
input int      inp_CopierPollMs             = 50;                   // Copy/close scan speed (ms)
input ENUM_STARTUP_COPY_MODE inp_CopierStartupCopyMode = COPY_NEW_TRADES_ONLY; // Startup Copy Mode
// --- Copier Lot Sizing (Slave only) ---
input group " ";
input group "--- Copier Lot Sizing ---";
input ENUM_COPIER_LOT_MODE inp_CopierLotMode = COPIER_LOT_COPY_MASTER; // Slave lot mode
input double   inp_CopierFixedLot           = 0.01;                 // Fixed lot size (if mode=Fixed)
input double   inp_CopierLotMultiplier      = 1.0;                  // Multiplier on master lot (if mode=Multiplier)
input double   inp_CopierRiskPercent        = 1.0;                  // Risk % of balance per trade (if mode=Risk%)
input double   inp_CopierMaxLot             = 10.0;                 // Max lot cap for copier
input double   inp_CopierMinimumLotToCopy   = 0.0;                  // Minimum Lot To Copy
input ENUM_TRADE_COMMENT_MODE inp_CopierTradeCommentMode = TRADE_COMMENT_DEFAULT; // Copier Trade Comment Mode
input string   inp_CopierCustomTradeComment = "Copy";               // Copier Custom Trade Comment
input group " ";
input group "--- Activity Report ---";
input bool     inp_EnableReportLog          = true;                 // Write activity report file
input int      inp_ReportPurgeDays          = 1;                    // Auto-delete report entries older than N days


input group "=== Advanced: Telegram Broadcast ===";
input bool     inp_EnableTelegramSend    = false;           // Copy trades forward to a channel
input string   inp_TelegramSendTag       = "[TCU]";         // Tag prefix for broadcast messages
input string   inp_TelegramSendSuffix    = "";              // Custom text appended to broadcast (e.g. your channel name)
input bool     inp_UseSeparateSendBot    = false;           // Use a different bot for sending
input string   inp_SendBotToken          = "";              // Separate bot token (if enabled)
input string   inp_SendChatID            = "";              // Separate chat/group ID (if enabled)


input group "=== LOT SIZING & RISK ===";
input ENUM_LOT_MODE inp_LotMode          = LOT_FIXED;
input double   inp_FixedLotSize          = 0.01;
input double   inp_LotMultiplier         = 1.0;                 // Legacy unused (kept for backward compatibility)
input double   inp_RiskPercent           = 1.0;
input string   inp_PerSymbolLots         = "";                  // [v6.00] Per-symbol lot overrides, e.g. "EURUSD=0.05, XAUUSD=0.03" (max 20 entries, MarketWatch only)
input int      inp_DefaultSLPoints       = 500;           // Default SL in points if signal has none (for risk calc)
input double   inp_MaxLotSize            = 10.0;
input bool     inp_SkipIfLotOverMax         = false;            // Skip if lot > MaxLotSize
input int      inp_MaxTradesPerMinute    = 0;             // Circuit breaker: max trades per 60s (0=unlimited)
input int      inp_MaxOpenPositions      = 20;            // Max open positions allowed (0=unlimited)


input group "=== SAFETY FILTERS & OVERRIDES ===";
input group " ";
input group "--- Daily Loss Protection ---";
input double   inp_MaxDailyLossPercent     = 0;                // Max daily loss % of balance (0=off) -- stops ALL trading if hit
input double   inp_MaxDailyLossAmount      = 0;                // Max daily loss $ amount (0=off) -- stops ALL trading if hit
input ENUM_DAILY_RESET_TZ inp_DailyResetTimezone = DAILY_TZ_BROKER; // [v6.01] Daily P/L boundary: BROKER server time (legacy) or UTC (most prop firms)
input bool     inp_DailyLossUsePeakEquity  = true;             // [v6.01] Also kill if drawdown from today's peak equity exceeds limit (catches "made profit then gave it back" scenarios prop firms penalise)
input group " ";
input group "--- Signal Validation ---";
input bool     inp_SkipSignalWithoutSL      = false;            // Skip signals with no SL (set true for prop firms)
input bool     inp_SkipSignalWithoutTP      = false;            // Skip signals with no TP
input bool     inp_EnableSignalTP           = true;             // Read TP/TP1/TP2/TP3 from incoming signals
input bool     inp_EnableAutoSL             = false;            // Add auto SL if signal is missing it
input int      inp_FallbackSLPips           = 0;                // Auto SL distance (pips)
input bool     inp_EnableAutoTP             = false;            // Add auto TP if signal is missing it
input int      inp_FallbackTPPips           = 0;                // Auto TP distance (pips)
input group " ";
input group "--- Time Filter ---";
input bool     inp_EnableTimeFilter         = false;            // Only execute during allowed hours
input int      inp_TimeFilterStartHour      = 0;                // Start hour (0-23)
input int      inp_TimeFilterEndHour        = 23;               // End hour (0-23)
input int      inp_SignalCooldownMinutes    = 3;              // Cooldown: ignore new signals for same symbol+direction (minutes, 0=disabled)

input bool     inp_AllowSLTPModDuringCooldown = true;       // Allow SL/TP modification signals during cooldown period
input double   inp_MinPipsDistanceSameType  = 0;                // Min pips between same-dir trades (0=off)
input group " ";
input group "--- Symbol Whitelist / Blacklist ---";
input bool     inp_EnableWhitelist       = false;           // ON = only trade symbols in WhitelistSymbols
input string   inp_WhitelistSymbols      = "";              // Comma-separated (e.g. "XAUUSD,BTCUSD,EURUSD")
input bool     inp_EnableBlacklist       = false;           // ON = block symbols in BlacklistSymbols
input string   inp_BlacklistSymbols      = "";              // Comma-separated symbols to block
input group " ";
input group "--- Keyword Filters ---";
input bool     inp_EnableSkipKeywords      = true;           // Skip messages containing status/notification keywords
input string   inp_SkipKeywords            = "";             // Comma-separated skip phrases (e.g. "HIT TP,RUNNING,CLOSED")


input group "=== TRADE MANAGEMENT ===";
input group " ";
input group "--- Pending Orders ---";
input bool     inp_EnablePendingOrders     = true;             // Accept BUY LIMIT/SELL LIMIT/BUY STOP/SELL STOP signals
input bool     inp_EnablePendingExpiry     = true;             // [v6.00 DEFAULT] Auto-delete pending orders not filled within time limit
input bool     inp_EnablePendingMultiTP    = true;             // Split pending orders into legs for each TP (uses LotDistribution)

input int      inp_PendingExpiryHours      = 24;               // Hours before unfilled pending order is deleted (if EnablePendingExpiry=true)
input group " ";
input group "--- SL / TP & Entry Copy ---";
input bool     inp_RequireEntryArmour      = false;            // ARMOUR: Require direction + symbol + (SL or TP or entry) -- OFF by default (accepts all signals)
input bool     inp_ModifySLTPIfPositionExists = true;          // Legacy setting kept for compatibility; cooldown modify behavior now uses AllowSLTPModDuringCooldown
input bool     inp_CopySL                = true;
input bool     inp_CopyTP                = true;
input bool     inp_ReverseSignal         = false;
input group " ";
input group "--- Symbol Mapping ---";
input string   inp_SymbolSuffix          = "";
input string   inp_CustomMappings        = "";
input group " ";
input group "--- Custom Keywords ---";
input bool     inp_EnableCustomSLTPKeywords = false;        // Enable custom SL/TP keyword matching
input string   inp_CustomSLKeywords       = "";             // Comma-separated SL keywords (e.g. "STOP,RISKAT,INVALIDATION")
input string   inp_CustomTPKeywords       = "";             // Comma-separated TP keywords (e.g. "TARGET,GOAL,EXIT")
input group " ";
input group "--- Command Replies ---";
input bool     inp_EnableCommandReplies     = false;            // React to "move sl", "close all"
input string   inp_MoveSLCommands           = "move sl entry,move sl to breakeven";
input string   inp_CloseAllCommands         = "close all";
input group " ";
input group "--- Keyword Replace ---";
input bool     inp_EnableKeywordReplace     = false;            // Replace keywords before parsing
input string   inp_KeywordReplaceMap        = "";               // "Stoploss=SL,Take Profit=TP"

input group "--- Advanced: Trailing Stop ---";
input bool     inp_EnableTrailingStop    = false;           // Enable trailing stop for positions with our magic number
input int      inp_TrailStartPips        = 10;              // Pips profit needed to activate trailing
input int      inp_TrailDistancePips     = 5;               // How close stop follows price (in pips)
input int      inp_TrailStepPips         = 1;               // Minimum pip step to move stop
input bool     inp_TrailMoveToBreakeven  = true;            // Move stop to breakeven when trailing activates
input int      inp_BreakevenBufferPips   = 0;               // Extra pips beyond entry for manual/trailing breakeven

input group "--- Advanced: Auto Profit Lock (Pips-Based) ---";
input ENUM_PARTIAL_MODE inp_PartialCloseMode = PARTIAL_PERCENTAGE; // Partial close: use % or fixed lots
input bool     inp_EnablePartialClose      = false;           // Auto-close portions of trade at pip milestones
input ENUM_PARTIAL_SCOPE inp_PartialScope  = PARTIAL_SCOPE_AUTO; // AUTO ignores signal Multi-TP split trades
input double   inp_PartialTP1Pips          = 0;               // TP1: pips profit to partial close (0=skip)
input double   inp_PartialTP1Lots          = 0.0;             // TP1: Fixed lots to close (0 = use %)
input double   inp_PartialTP1Percent       = 0;               // TP1: % of position to close
input double   inp_PartialTP2Pips          = 0;               // TP2: pips profit to partial close (0=skip)
input double   inp_PartialTP2Lots          = 0.0;             // TP2: Fixed lots to close
input double   inp_PartialTP2Percent       = 0;               // TP2: % of position to close
input double   inp_PartialTP3Pips          = 0;               // TP3: pips profit to partial close (0=skip)
input double   inp_PartialTP3Lots          = 0.0;             // TP3: Fixed lots to close
input double   inp_PartialTP3Percent       = 0;               // TP3: % of position to close
input double   inp_PartialTP4Pips          = 0;               // TP4: pips profit to partial close (0=skip)
input double   inp_PartialTP4Lots          = 0.0;             // TP4: Fixed lots to close
input double   inp_PartialTP4Percent       = 0;               // TP4: % of position to close
input bool     inp_PartialMoveSLBreakeven  = true;            // Move SL to breakeven after TP1
input int      inp_PartialBEExtraPips      = 0;               // Extra pips above entry for breakeven
input bool     inp_PartialMoveSLToTP1      = false;           // Move SL to TP1 price when TP2 hits
input bool     inp_PartialMoveSLToTP2      = false;           // Move SL to TP2 price when TP3 hits
input bool     inp_PartialMoveSLToTP3      = false;           // Move SL to TP3 price when TP4 hits

input group "--- Advanced: Signal TP Splitting ---";
input bool     inp_EnableMultiTP            = true;            // Auto-split into separate trades if signal has TP2/TP3
input int      inp_MaxTPTargets             = 3;               // Max TPs to extract (1-3)
input ENUM_PARTIAL_MODE inp_SignalTpAllocMode = PARTIAL_PERCENTAGE; // Signal TP split: use % or fixed lots
input bool     inp_SignalTpFixedOverrideMainLots = false;      // When Signal TP mode=FIXED LOTS, use TP lot values directly instead of scaling to main lots
input string   inp_LotDistribution          = "40,30,30";      // Volume % split per signal TP
input string   inp_SignalTpLotValues        = "0.00,0.00,0.00"; // Fixed lots per TP when SignalTpAllocMode=FIXED LOTS
input bool     inp_TGMoveSLBreakevenTP1     = false;           // Move SL to breakeven when TP1 closes
input bool     inp_TGMoveSLToTP1OnTP2       = false;           // Move SL to TP1 price when TP2 closes
input int      inp_TGBreakevenExtraPips     = 0;               // Extra pips for breakeven


input group "=== * SAFETY & PROFILE ===";
input group " ";
input group "--- Execution Control ---";
input bool     inp_ArmExecution             = false;           // ARM: EA will place live trades (false = no trades, safe/testing mode)
input bool     inp_DisarmOnRestart          = false;           // Keep armed across chart changes/recompiles; set true if you want a safety disarm on every restart
input bool     inp_EnableDuplicateFilter     = true;             // [v6.00 DEFAULT] Block duplicate signals (multi-channel forwarding safety) -- turn OFF for testing only
input int      inp_DuplicateWindowMinutes    = 5;                // Exact same signal text blocked for this many minutes after successful processing
input group " ";
input group "--- Mode Overrides ---";
input bool     inp_PropFirmMode             = false;           // PROP FIRM: Force SL required, daily loss cap, no multi-entry same symbol
input group " ";
input group "--- Martingale Unlock (Advanced) ---";
input bool     inp_ShowMartingaleTab        = false;          // ADVANCED: Unhides the Martingale tab — password also required
input string   inp_MartingalePassword       = "";             // ADVANCED: Enter unlock password to enable Martingale tab (contact support)
input string   inp_MGPerSymbolLots          = "";             // MG per-symbol base lot overrides e.g. "XAUUSD=0.05,BTCUSD=0.1" (falls back to MartingaleBaseLot if not matched)
input group " ";
input group "--- Diagnostics ---";
input bool     inp_EnableDiagLog            = false;          // [v6.00 DEFAULT] DIAG: Write full signal trace log to file (for debugging) -- opt-in for privacy
input string   inp_DiagLogFileName          = "TCU_STRESS_Log.txt"; // DIAG: Log file name in MQL5/Files/Common

input group "=== NEWS PAUSE ENGINE ===";
input bool     inp_EnableNewsPause          = false;          // Pause new entries around MT5 calendar news
input int      inp_NewsPauseBeforeMinutes   = 5;              // Minutes before news to pause entries
input int      inp_NewsPauseAfterMinutes    = 5;              // Minutes after news to resume entries
input bool     inp_NewsPauseHighImpact      = true;           // Include high impact events
input bool     inp_NewsPauseMediumImpact    = true;           // Include medium impact events
input string   inp_NewsPauseCurrencies      = "USD,EUR,GBP,JPY,AUD,CAD,CHF,NZD"; // Currencies to watch

input group "=== GENERAL SETTINGS ===";

input int      inp_MagicNumber           = 333333;
input ENUM_PANEL_MODE inp_PanelMode      = PANEL_FULL;
input int      inp_PanelX                = 20;
input int      inp_PanelY                = 50;
input bool     inp_EnableSpreadFilter        = false;             // Enable max spread filter (skip trades if spread too high)
input int      inp_MaxSpreadPoints           = 50;               // Max allowed spread in points (only if EnableSpreadFilter=true)
input bool     inp_EnableSlippageFilter      = false;             // Enable slippage filter
input int      inp_SlippagePoints            = 10;
input double   inp_EntrySlippagePips         = 0;                // Max entry slippage pips (0=disabled, only if EnableSlippageFilter=true)
input ENUM_SLIPPAGE_ACTION inp_SlippageAction = SLIP_SKIP_SIGNAL;
input ENUM_OPPOSITE_ACTION inp_OppositeAction = OPP_NOTHING;
input bool     inp_EnablePopupAlerts     = true;
input bool     inp_EnableSoundAlerts     = true;
input bool     inp_EnablePushNotify      = false;
input bool     inp_EnablePartialAlerts   = true;
input string   inp_AlertSoundFile        = "alert.wav";

// --- SHADOW GLOBALS (mutable copies of inputs) -------------------------------
bool EnableBotAPIMode;
string TelegramBotToken;
string TelegramChatID;
int TelegramPollSeconds;
bool EnableBridgeMode;
int BridgePort;
int BridgePollMs;
string AllowedBridgeSources;
bool EnableDiscordMode;
string DiscordWebhookURL;
int DiscordPollSeconds;
ENUM_COPIER_MODE CopierMode;
string CopierFileName;
bool CopierAutoClose;
int CopierPollMs;
ENUM_STARTUP_COPY_MODE CopierStartupCopyMode;
ENUM_COPIER_LOT_MODE CopierLotMode;
double CopierFixedLot;
double CopierLotMultiplier;
double CopierRiskPercent;
double CopierMaxLot;
double CopierMinimumLotToCopy;
ENUM_TRADE_COMMENT_MODE CopierTradeCommentMode;
string CopierCustomTradeComment;
bool EnableReportLog;
int ReportPurgeDays;
bool EnableTelegramSend;
string TelegramSendTag;
string TelegramSendSuffix;
bool UseSeparateSendBot;
string SendBotToken;
string SendChatID;
ENUM_LOT_MODE LotMode;
double FixedLotSize;
double LotMultiplier;
double RiskPercent;
string PerSymbolLots;        // [v6.00 NEW][PerSymbolLots] Raw input string, parsed at use time.
// MGPerSymbolLots is declared in the MG state block above; mirrored from inp_MGPerSymbolLots in OnInit.
int DefaultSLPoints;
double MaxLotSize;
bool SkipIfLotOverMax;
int MaxTradesPerMinute;
int MaxOpenPositions;
double MaxDailyLossPercent;
double MaxDailyLossAmount;
ENUM_DAILY_RESET_TZ DailyResetTimezone;   // [v6.01 FIX] runtime mirror of inp_DailyResetTimezone
bool DailyLossUsePeakEquity;              // [v6.01 FIX] runtime mirror of inp_DailyLossUsePeakEquity
bool SkipSignalWithoutSL;
bool SkipSignalWithoutTP;
bool EnableSignalTP;
bool EnableAutoSL;
int FallbackSLPips;
bool EnableAutoTP;
int FallbackTPPips;
bool EnableTimeFilter;
int TimeFilterStartHour;
int TimeFilterEndHour;
   int SignalCooldownSeconds;

bool AllowSLTPModDuringCooldown;
double MinPipsDistanceSameType;
bool EnableWhitelist;
string WhitelistSymbols;
bool EnableBlacklist;
string BlacklistSymbols;
bool EnableSkipKeywords;
string SkipKeywords;
bool EnablePendingOrders;
bool EnablePendingExpiry;

bool EnablePendingMultiTP;
int PendingExpiryHours;
bool RequireEntryArmour;
bool ModifySLTPIfPositionExists;
bool CopySL;
bool CopyTP;
bool ReverseSignal;
string SymbolSuffix;
string CustomMappings;
bool EnableCustomSLTPKeywords;
string CustomSLKeywords;
string CustomTPKeywords;
bool EnableCommandReplies;
string MoveSLCommands;
string CloseAllCommands;
bool EnableKeywordReplace;
string KeywordReplaceMap;
bool EnableTrailingStop;
int TrailStartPips;
int TrailDistancePips;
int TrailStepPips;
bool TrailMoveToBreakeven;
int BreakevenBufferPips;
bool EnablePartialClose;
ENUM_PARTIAL_SCOPE PartialScope;
double PartialTP1Pips;
double PartialTP1Lots;
double PartialTP1Percent;
double PartialTP2Pips;
double PartialTP2Lots;
double PartialTP2Percent;
double PartialTP3Pips;
double PartialTP3Lots;
double PartialTP3Percent;
double PartialTP4Pips;
double PartialTP4Lots;
double PartialTP4Percent;
bool PartialMoveSLBreakeven;
int PartialBEExtraPips;
bool PartialMoveSLToTP1;
bool PartialMoveSLToTP2;
bool PartialMoveSLToTP3;
bool EnableMultiTP;
int MaxTPTargets;
ENUM_PARTIAL_MODE SignalTpAllocMode;
bool SignalTpFixedOverrideMainLots;
string LotDistribution;
string SignalTpLotValues;
bool TGMoveSLBreakevenTP1;
bool TGMoveSLToTP1OnTP2;
int TGBreakevenExtraPips;
bool ArmExecution;
bool DisarmOnRestart;
bool EnableDuplicateFilter;
int  DuplicateWindowMinutes;
bool PropFirmMode;
bool EnableDiagLog;
string DiagLogFileName;
bool EnableNewsPause;
int NewsPauseBeforeMinutes;
int NewsPauseAfterMinutes;
bool NewsPauseHighImpact;
bool NewsPauseMediumImpact;
string NewsPauseCurrencies;
int MagicNumber;
ENUM_PANEL_MODE PanelMode;
ENUM_PARTIAL_MODE PartialCloseMode;
int PanelX;
int PanelY;
bool EnableSpreadFilter;
int MaxSpreadPoints;
bool EnableSlippageFilter;
int SlippagePoints;
double EntrySlippagePips;
ENUM_SLIPPAGE_ACTION SlippageAction;
ENUM_OPPOSITE_ACTION OppositeAction;
bool EnablePopupAlerts;
bool EnableSoundAlerts;
bool EnablePushNotify;
bool EnablePartialAlerts;
int g_signalCooldownRestoreMinutes = 3;
string AlertSoundFile;

// ===========================================================================
// MARTINGALE SYSTEM STATE
// ===========================================================================
bool   EnableMartingale        = false;
int    MartingaleMode          = 0;    // 0=Classic(x2) 1=Custom 2=AntiMartingale 3=FixedStep
double MartingaleMultiplier    = 2.0;
double MartingaleFixedStep     = 0.01; // lots added per loss (FixedStep mode)
double MartingaleBaseLot       = 0.01; // base lot for martingale series (0 = use EA lot calculator)
string MGPerSymbolLots         = "";  // per-symbol MG base lot overrides (mirrors inp_MGPerSymbolLots)
int    MartingaleMaxSteps      = 4;
bool   MartingaleResetOnWin    = true;
int    g_mgViewTab             = 0;    // 0=Strategies view 1=Recovery view (UI nav only, NOT the active mode)
bool   g_mgHelpOpen            = false; // true = show how-to-use overlay on Martingale tab
bool   g_showMartingaleTab     = false; // true only when BOTH inp_ShowMartingaleTab AND inp_MartingaleRiskAccepted are true
int    g_mgHelpPage            = 0;     // 0=Classic 1=Custom 2=AntiMartin 3=FixedStep 4=Recovery
datetime g_mgActivationTime    = 0;     // Fresh-enable fence: closes before this time never count toward the live streak

// Recovery mode (Mode 4) is fully loss-driven -- no user settings.
// Each recovery lot is sized from the carried loss + the signal's own TP profit.
double MartingaleMaxLoss       = 0;     // Safety: stop increasing lots if cumulative loss exceeds this $ amount (0 = disabled)

// Per-symbol streak tracking
struct MG_Entry { string sym; int streak; double mgPnl; int wins; int losses; double lastPnl; double carry; double recTarget; };
MG_Entry g_mgTable[];
int      g_mgCount = 0;
bool     g_mgDisclaimerAccepted = false; // intentionally NOT saved — resets every EA attach
// [MG] Deal deduplication: prevents OnTradeTransaction firing twice for the same deal
// [FIX] Increased from 256 → 2048: the circular buffer must outlive 24 h of deal history
// across all symbols so MG_InitDealCache() never overwrites its own oldest entries.
#define  MG_DEAL_CACHE 2048
ulong    g_mgProcessedDeals[MG_DEAL_CACHE];
int      g_mgProcessedHead = 0;

//--- Defines
#define PREFIX "TCU_"

// --- STYLE-C PANEL ----------------------------------------------------------
#define SC_PFX   "SC_"
#define SC_W     500
#define SC_SIDE  76
#define SC_CW    (SC_W-SC_SIDE)
#define SC_RH    24
#define SC_BGC   C'10,10,20'
#define SC_SBC   C'16,18,28'
#define SC_HDC   C'18,20,32'
#define SC_AC    C'0,200,140'
#define SC_NAC   C'18,36,22'
#define SC_TC    clrWhite
#define SC_DC    C'110,115,130'
#define SC_IBG   C'28,30,45'
#define SC_IBD   C'50,55,75'
#define SC_OK    C'0,180,100'
#define SC_WN    C'200,150,0'
#define SC_NG    C'200,50,50'
#define SC_DV    C'35,38,55'
#define SC_SC    C'0,175,120'
#define SC_TABS  6

#define TELEGRAM_URL "https://api.telegram.org/bot"
// Configurable timeouts (in milliseconds)
#define SYMBOL_LOAD_TIMEOUT 500
#define POSITION_REGISTER_TIMEOUT 200
#define SLTP_MODIFY_TIMEOUT 50
#define FILE_RETRY_TIMEOUT 10
#define COPIER_EMPTY_CLOSE_CONFIRM_READS 2

//--- Global Variables
CTrade g_trade;
bool g_isTester = false;
int g_lastUpdateId = 0;
ulong g_lastTelegramPoll = 0;
ulong g_lastFileScan = 0;
ulong g_lastManualCheck = 0;
ulong g_lastBridgePoll = 0;
int g_bridgeFailCount = 1; // Start at 1
bool g_bridgeFirstPoll = true; // Skip stale signals on first bridge poll
long g_bridgeAckIds[];         // Signal IDs received this poll -> targeted /signals/clear ACK

ulong g_startupTickCount = 0;   // Tick count at EA start, used for 10s startup drain
ulong g_bridgeNextRetry = 0; // Set in OnInit to delay first poll by 5s
int g_tradesReceived = 0;
int g_tradesSent = 0;
string g_lastFilterReason = "";  // Last reason a signal was rejected (shown on panel)
int g_signalsProcessed = 0;
string g_lastSignal = "";
string g_lastError = "";
string g_currentMode = "";
string g_autoSuffix = "";  // Auto-detected broker suffix (e.g. ".m", "_SB", ".stp")
ulong g_sentAlertTickets[];
ulong g_copiedTickets[];
ulong g_slaveTickets[];
ulong g_masterTicketMap[];
double g_masterLots[];      // Track master lot sizes for partial close detection
ulong g_processedHashes[];
datetime g_processedHashTimes[];
// [v6.00 FIX 2026-04-26][R2] Defer dedup persistence until execution success.
// g_currentSignalHash holds the hash of the signal currently being processed; it's persisted
// via MarkProcessed() ONLY after a successful trade send (or successful command), not at the
// top of ProcessTextSig. This way, signals rejected by transient filters (news pause, spread
// spike, prop firm SL missing, insufficient margin) can be re-sent and re-processed instead
// of being permanently locked out the moment they first arrive.
ulong g_currentSignalHash = 0;
string g_currentSignalRef  = "";   // Signal ref from bridge (NTSxxxxxxxx) for ticket callback
string g_aliasNames[];
string g_aliasSymbols[];
int g_aliasCount = 0;
int g_emptyReadCount = 0;  // Counter for race-condition-safe close management
int g_initialSyncEmptyReadableScans = 0; // Guard against false "empty" first snapshot while master is writing
string g_tgQueue[];         // Non-blocking Telegram send queue
int g_tgQueueSize = 0;
int g_tgQueueRetries[];     // Retry counters for Telegram queue
string g_dcQueue[];         // Non-blocking Discord send queue
int g_dcQueueSize = 0;
int g_dcQueueRetries[];     // Retry counters for Discord queue
datetime g_tgSenderStartTime = 0;
datetime g_dcSenderStartTime = 0;
ulong g_lastTimerFire = 0;  // Track timer health for restart recovery
int g_timerMs = 50;         // Saved timer interval
bool g_scanInProgress = false;   // Re-entrancy guard for ScanCopierFile
bool g_writeInProgress = false;  // Re-entrancy guard for WriteMasterTrades
string g_mapCacheIn[];
string g_mapCacheOut[];
int    g_mapCacheCount = 0;
datetime g_dailyLossCacheInvalidAfter = 0;
// [v6.01 FIX] Day-anchored balance + peak equity for prop-firm-correct daily-loss math.
// Captured once per day-rollover (see TCU_RolloverDailyAnchorIfNeeded). The legacy
// implementation anchored to *current* balance which masked "made profit then gave it
// back" drawdowns -- exactly what prop firms blow accounts for.
double   g_dailyStartBalance = 0;     // Balance captured at day-rollover
double   g_dailyPeakEquity   = 0;     // Highest equity reached today (updated continuously)
datetime g_dailyAnchorDate   = 0;     // Day-stamp (00:00 of the configured TZ) of the current anchor
ulong  g_sltpOrderTickets[];
ulong  g_sltpDealTickets[];
ulong  g_sltpLiveTickets[];
string g_sltpSymbols[];
int    g_sltpPosTypes[];
double g_sltpSLs[];
double g_sltpTPs[];
string g_sltpContexts[];
int    g_sltpAttempts[];
ulong  g_sltpQueuedAt[];
int    g_sltpQueueCount = 0;

// Heartbeat ticket buffer — backup /callback path for prop-mode reliability
string g_hbRefBuf[];
ulong  g_hbTicketBuf[];
string g_hbSymBuf[];
int    g_hbBufCount = 0;

// --- 4-LAYER SYMBOL RESOLVER (v6.00) -----------------------------------
// Ported from Navigator receiver: covers 60+ broker suffixes + 150+ aliases,
// strip/add/strip-then-add suffix mutation, bidirectional alias dictionary,
// and scored MarketWatch scan with exact-case return.
string g_sfxList[];             // All known broker suffixes
int    g_sfxCount = 0;
string g_naliasA[];             // Bidirectional alias side A
string g_naliasB[];             // Bidirectional alias side B
int    g_naliasCount = 0;

// State file for slave persistence across restarts
string g_stateFileName = "";  // Set in OnInit based on CopierFileName
string g_botStateFileName = "";  // Bot API state persistence (update_id)
bool g_botStateLoaded = false;  // Track if we loaded existing state (vs first run)
bool g_botFirstPollDone = false; // ALWAYS skip old messages on first poll after EA start
// [v6.01 CRITICAL FIX] Bot session start (server time, GMT). Any Telegram
// message whose own "date" field is older than this is dropped REGARDLESS of
// flush / update_id state. This is the last-line defence against replaying
// historical signals after a fresh EA attach -- the failure mode that caused
// real-money users to wake up to surprise trades from yesterday's chat
// history. Updated on OnInit and on every panel toggle of Bot API mode.
datetime g_botSessionStartTime = 0;
// Tolerance window: messages within this many seconds of session start are
// allowed. Telegram "date" is Unix UTC and TimeGMT() is UTC, so this is just
// clock-skew + WebRequest jitter margin -- 5 s is the right call. 60 s would
// let signals posted up to a minute before activation slip through, which is
// not what a real-money copier wants.
#define TCU_BOT_SESSION_TOLERANCE_SEC 5

// Duplicate trade cooldown (5-second per symbol+direction)
string g_lastTradeSyms[];
string g_lastTradeDirs[];
ulong  g_lastTradeTimes[];
int    g_lastTradeCount = 0;

// Circuit breaker: track recent trade timestamps
ulong g_recentTradeTimes[];
int   g_recentTradeCount = 0;

// Telegram polling backoff on errors
int   g_telegramFailCount = 0;

// Missing variable declarations (referenced but not declared)
bool g_initialSyncDone = false;  // Track if slave's first scan completed
bool g_masterSynced = false;     // Track if master has synced positions from server
datetime g_slaveStartTime = 0;   // When slave started (to filter old master trades)
datetime g_eaStartTime = 0;      // When EA was initialized (to filter old bridge/bot signals)
string g_reportFileName = "";    // Report log file name
int g_initialSyncSnapshotCount = -1;
ulong g_initialSyncSnapshotHash = 0;
ulong g_slaveActivationGuardUntil = 0;
int g_slaveActivationGuardMs = 10000;
ulong g_masterActivationBaselineUntil = 0;
int g_masterActivationBaselineMs = 10000;
datetime g_masterActivationTime = 0;
bool g_testerTraded = false;        // MQL5 Market validation: track if tester trade done
ulong g_testerTicket = 0;           // MQL5 Market validation: ticket to close on next tick

// Manual Partial Close tracking
ulong  g_partialTickets[];
bool   g_partialTP1Done[];
bool   g_partialTP2Done[];
bool   g_partialTP3Done[];
bool   g_partialTP4Done[];
double g_partialOrigLots[];
int    g_partialCount = 0;

// Pending order auto-expiry tracking
ulong    g_pendingExpTickets[];
datetime g_pendingExpTimes[];

// Telegram Multi-TP tracking
string g_mtpGroupIDs[];
ulong  g_mtpTickets[];
int    g_mtpTPIndex[];
double g_mtpTPPrices[];
double g_mtpEntryPrices[];
int    g_mtpCount = 0;

// Panel state (must be declared before OnChartEvent)
int  g_panelX = 10;
int  g_panelY = 30;
int  g_panelW = 280;
int  g_panelH = 380;
bool g_minimized = false;
bool g_dragging = false;
int  g_dragOffsetX = 0;
int  g_dragOffsetY = 0;
color g_clrBG     = C'26,26,46';
color g_clrHDR    = C'20,20,36';
color g_clrBorder = C'55,55,90';
color g_clrAccent = C'0,212,255';
color g_clrText   = C'220,220,240';
color g_clrDim    = C'100,100,130';
color g_clrSafe   = C'0,200,100';
color g_clrWarn   = C'255,200,0';
color g_clrDanger = C'200,30,30';

// Trigger Pro canvas UI state
#define TCUC_PFX      "TCUC_"
#define TCUC_W        360
#define TCUC_H        620
#define TCUC_MINI_W   430
#define TCUC_MINI_H   62
#define TCUC_CONTENT_Y 192
#define TCUC_CONTENT_Y_COMPACT 148

struct TcuHit
{
   string name;
   int x;
   int y;
   int w;
   int h;
};

CCanvas g_tcuCanvas;
bool    g_tcuCanvasCreated = false;
int     g_tcuCanvasW = 0;
int     g_tcuCanvasH = 0;
TcuHit  g_tcuHits[];
int     g_tcuHitCount = 0;
int     g_tcuTab = 0;
int     g_tcuSettingsCat = 0;
string  g_tcuHovered = "";
string  g_tcuPressed = "";
string  g_tcuLastTimerSnapshot = "";
bool    g_tcuDragging = false;
int     g_tcuDragOffsetX = 0;
int     g_tcuDragOffsetY = 0;
bool    g_tcuMouseWasDown = false;
int     g_tcuMouseDownX = 0;
int     g_tcuMouseDownY = 0;
string  g_tcuMouseDownHit = "";
bool    g_tcuClosed = false;
string  g_tcuActiveEdit = "";
string  g_tcuActiveEditStart = "";
string  g_tcuLastSavedStringState = "";
bool    g_tcuSettingsDirty = false;
ulong   g_tcuSettingsDirtyAt = 0;
string  g_tcuVisibleEdits[];
int     g_tcuVisibleEditCount = 0;
int     g_tcuFilterScroll = 0;

#define TCUO_W 336
#define TCUO_H 454

CCanvas g_tcuMonCanvas;
bool    g_tcuMonCreated = false;
bool    g_tcuMonOpen = false;
int     g_tcuMonX = -1;
int     g_tcuMonY = -1;
TcuHit  g_tcuMonHits[];
int     g_tcuMonHitCount = 0;
string  g_tcuMonHovered = "";
string  g_tcuMonPressed = "";
bool    g_tcuMonDragging = false;
int     g_tcuMonDragOffsetX = 0;
int     g_tcuMonDragOffsetY = 0;
bool    g_tcuMonMouseWasDown = false;
int     g_tcuMonMouseDownX = 0;
int     g_tcuMonMouseDownY = 0;
string  g_tcuMonMouseDownHit = "";
int     g_tcuMonTab = 0;          // 0=Trades, 1=Orders
int     g_tcuMonTradeScroll = 0;
int     g_tcuMonOrderScroll = 0;
ulong   g_tcuMonSelectedTicket = 0;
bool    g_tcuMonSelectedIsOrder = false;

// [v6.00 NEW][PerSymUI] Per-Symbol Lots configurator modal popup state.
// Mirrors the Trade Monitor popup pattern: separate canvas, separate hit-test buffer,
// click events routed via TCU_HandleCanvasEvent before the main panel.
#define TCU_PSL_W 392
#define TCU_PSL_H 482
// Hoist the per-symbol cap so the new UI helpers (Psl_*) -- which live earlier in
// the file than the legacy text-field validator -- see the same constant.
#ifndef TCU_PERSYMBOL_MAX
#define TCU_PERSYMBOL_MAX 20
#endif
CCanvas g_tcuPslCanvas;
bool    g_tcuPslCreated = false;
bool    g_tcuPslOpen = false;
int     g_tcuPslX = -1;
int     g_tcuPslY = -1;
int     g_tcuPslScroll = 0;
TcuHit  g_tcuPslHits[];
int     g_tcuPslHitCount = 0;
string  g_tcuPslHovered = "";
string  g_tcuPslPressed = "";
bool    g_tcuPslDragging = false;
int     g_tcuPslDragOffsetX = 0;
int     g_tcuPslDragOffsetY = 0;
bool    g_tcuPslMouseWasDown = false;
int     g_tcuPslMouseDownX = 0;
int     g_tcuPslMouseDownY = 0;
string  g_tcuPslMouseDownHit = "";
string  g_tcuPslAddInputCache = "";   // last value typed into the Add input on the Lots settings tab
string  g_tcuPslAddBanner = "";       // transient feedback after Add (e.g. "added EURUSD" / "not in MarketWatch")
ulong   g_tcuPslAddBannerAt = 0;      // timestamp so banner auto-clears after a few seconds
bool    g_tcuPslIsMGMode      = false;   // true = popup is editing MGPerSymbolLots instead of PerSymbolLots
bool    g_tcuAdvSetOpen      = false;   // Advanced mode settings overlay popup
string  g_mgpslLastSerialized  = "";      // idempotent parse cache for MG-mode (separate from main lots cache)
bool    g_pslLastParseWasMG    = false;   // tracks mode of last parse to detect mode switches
// Parsed entries (parallel arrays). Authoritative copy lives in PerSymbolLots string;
// these arrays are rebuilt from the string whenever it changes externally and serialized
// back via Psl_SerializeToString() after any add/remove/adjust/reorder operation.
string  g_pslKeys[];
double  g_pslLots[];
string  g_pslResolved[];   // [v6.00 NEW][PerSymUI] Cached MarketWatch lookup result per entry. Refreshed on parse / add / remove / move only -- not per draw.
int     g_pslCount = 0;
string  g_pslLastSerialized = "";

// [MG Monitor] Martingale Monitor popup state (mirrors Trade Monitor / PSL popup pattern)
#define TCU_MGM_W  380
#define TCU_MGM_H  448
#define TCU_ADV_W  340
#define TCU_ADV_H  355
#define TCU_PROF_W 320
#define TCU_PROF_H 194

CCanvas g_mgmCanvas;
bool    g_mgmCreated      = false;
bool    g_mgmOpen         = false;
int     g_mgmX            = -1;
int     g_mgmY            = -1;
TcuHit  g_mgmHits[];
int     g_mgmHitCount     = 0;
string  g_mgmHovered      = "";
string  g_mgmPressed      = "";
bool    g_mgmDragging     = false;
int     g_mgmDragOffsetX  = 0;
int     g_mgmDragOffsetY  = 0;
bool    g_mgmMouseWasDown = false;
int     g_mgmMouseDownX   = 0;
int     g_mgmMouseDownY   = 0;
string  g_mgmMouseDownHit = "";
int     g_mgmSelected     = -1;   // -1 = list view, >=0 = detail for that g_mgTable index

CCanvas g_advCanvas;
bool    g_advCreated      = false;
int     g_advX            = -1;
int     g_advY            = -1;
TcuHit  g_advHits[];
int     g_advHitCount     = 0;
string  g_advHovered      = "";
string  g_advPressed      = "";
bool    g_advDragging     = false;
int     g_advDragOffsetX  = 0;
int     g_advDragOffsetY  = 0;
bool    g_advMouseWasDown = false;
int     g_advMouseDownX   = 0;
int     g_advMouseDownY   = 0;
string  g_advMouseDownHit = "";

CCanvas g_profCanvas;
bool    g_profCreated      = false;
int     g_profX            = -1;
int     g_profY            = -1;
TcuHit  g_profHits[];
int     g_profHitCount     = 0;
string  g_profHovered      = "";
string  g_profPressed      = "";
bool    g_profDragging     = false;
int     g_profDragOffsetX  = 0;
int     g_profDragOffsetY  = 0;
bool    g_profMouseWasDown = false;
int     g_profMouseDownX   = 0;
int     g_profMouseDownY   = 0;
string  g_profMouseDownHit = "";
int     g_mgmScroll       = 0;

// [MG Monitor] Per-trade history recorded this session (capped at 200)
#define MG_HIST_MAX 200
string   g_mgHistSym[];
double   g_mgHistProfit[];
datetime g_mgHistTime[];
int      g_mgHistCount = 0;

struct TcuNewsEvent
{
   string name;
   string currency;
   datetime time;
   int impact;
};

TcuNewsEvent g_tcuNews[];
int      g_tcuNewsCount = 0;
datetime g_tcuNewsLastLoad = 0;
string   g_tcuNewsLockReason = "";
datetime g_tcuNewsLockUntil = 0;
datetime g_tcuLastNewsLog = 0;
int      g_tcuNewsScroll = 0;

color TCUC_BG      = C'15,18,25';
color TCUC_PNL     = C'22,26,36';
color TCUC_CARD    = C'24,30,42';
color TCUC_CARD2   = C'31,38,52';
color TCUC_GRID    = C'38,48,64';
color TCUC_DIV     = C'44,54,70';
color TCUC_ACC     = C'0,180,255';
color TCUC_OK      = C'0,230,118';
color TCUC_DNG     = C'255,45,85';
color TCUC_WARN    = C'255,160,0';
color TCUC_TXT     = clrWhite;
color TCUC_DIM     = C'110,120,140';
color TCUC_NOTE    = C'255,196,72';
color TCUC_HINT    = C'170,182,206';
color TCUC_BRD     = C'40,50,60';
color TCUC_CLOSE_H = C'196,43,28';
color TCUC_PURP    = C'140,60,255';

//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFillMode(string sym)
{
   long fillMode = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fillMode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

double PipSize(string sym)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0) return 0.0001;
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

double BreakevenSLPrice(string sym, bool isBuy, double entryPrice, int bufferPips)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double offset = MathMax(0, bufferPips) * PipSize(sym);
   return isBuy ? NormalizeDouble(entryPrice + offset, digits)
                : NormalizeDouble(entryPrice - offset, digits);
}

string UrlEncode(string s)
{
   string out = "";
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
   {
      ushort c = StringGetCharacter(s, i);
      bool safe = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z')
               || (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.' || c == '~';
      if(safe)
         out += ShortToString(c);
      else if(c < 0x80)
         out += StringFormat("%%%02X", c);
      else
      {
         uchar buf[4];
         int n = 0;
         if(c < 0x800)
         {
            buf[0] = (uchar)(0xC0 | (c >> 6));
            buf[1] = (uchar)(0x80 | (c & 0x3F));
            n = 2;
         }
         else
         {
            buf[0] = (uchar)(0xE0 | (c >> 12));
            buf[1] = (uchar)(0x80 | ((c >> 6) & 0x3F));
            buf[2] = (uchar)(0x80 | (c & 0x3F));
            n = 3;
         }
         for(int k = 0; k < n; k++)
            out += StringFormat("%%%02X", buf[k]);
      }
   }
   return out;
}

string JsonEscape(string s)
{
   string out = s;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   StringReplace(out, "\r", "\\r");
   StringReplace(out, "\n", "\\n");
   StringReplace(out, "\t", "\\t");
   return out;
}

//+------------------------------------------------------------------+
//|  NTS_ClientId — stable "<broker>|<account>" identity that the    |
//|  Bridge uses for per-MT5 routing and delivery tracking.          |
//|  Sent as `X-Client-Id` on /signals/copier, /signals/clear/copier |
//|  and /heartbeat. CR/LF are stripped so the header stays safe.    |
//+------------------------------------------------------------------+
string NTS_ClientId()
{
   string broker = AccountInfoString(ACCOUNT_COMPANY);
   // Header value must not contain CR/LF or the pipe we use as separator
   StringReplace(broker, "\r", "");
   StringReplace(broker, "\n", "");
   StringReplace(broker, "|",  "_");
   string account = StringFormat("%I64d", (long)AccountInfoInteger(ACCOUNT_LOGIN));
   return broker + "|" + account;
}

string CacheMap(string in, string out)
{
   for(int i = 0; i < g_mapCacheCount; i++)
      if(g_mapCacheIn[i] == in) return out;
   if(g_mapCacheCount >= 200) return out;

   ArrayResize(g_mapCacheIn, g_mapCacheCount + 1);
   ArrayResize(g_mapCacheOut, g_mapCacheCount + 1);
   g_mapCacheIn[g_mapCacheCount] = in;
   g_mapCacheOut[g_mapCacheCount] = out;
   g_mapCacheCount++;
   return out;
}

string HashFile()
{
   return "TCU_Hashes_" + IntegerToString(MagicNumber) + ".dat";
}

string HashToLine(ulong hash, datetime seenAt)
{
   ulong hi = (hash >> 32);
   ulong lo = (hash & 0xFFFFFFFF);
   return IntegerToString((long)hi) + ":" + IntegerToString((long)lo) + ":" + IntegerToString((int)seenAt);
}

bool ParseHashLine(string line, ulong &hash, datetime &seenAt)
{
   string parts[];
   int partCount = StringSplit(line, ':', parts);
   if(partCount != 2 && partCount != 3)
   {
      long legacy = StringToInteger(line);
      hash = (ulong)legacy;
      seenAt = 0;
      return (hash > 0);
   }
   StringTrimLeft(parts[0]);
   StringTrimRight(parts[0]);
   StringTrimLeft(parts[1]);
   StringTrimRight(parts[1]);
   if(StringLen(parts[0]) == 0 || StringLen(parts[1]) == 0) return false;

   ulong hi = (ulong)StringToInteger(parts[0]);
   ulong lo = (ulong)StringToInteger(parts[1]);
   hash = (hi << 32) | (lo & 0xFFFFFFFF);
   seenAt = 0;
   if(partCount == 3)
   {
      StringTrimLeft(parts[2]);
      StringTrimRight(parts[2]);
      if(StringLen(parts[2]) > 0)
         seenAt = (datetime)StringToInteger(parts[2]);
   }
   return (hash > 0);
}

int TCU_DuplicateWindowSeconds()
{
   return MathMax(1, DuplicateWindowMinutes) * 60;
}

int TCU_FindProcessedHashIndex(ulong hash)
{
   int sz = ArraySize(g_processedHashes);
   for(int i = 0; i < sz; i++)
      if(g_processedHashes[i] == hash) return i;
   return -1;
}

void TCU_PruneProcessedHashes()
{
   int sz = ArraySize(g_processedHashes);
   if(sz <= 0) return;

   datetime nowTs = TimeCurrent();
   int windowSec = TCU_DuplicateWindowSeconds();
   int writeIdx = 0;
   for(int i = 0; i < sz; i++)
   {
      datetime seenAt = (ArraySize(g_processedHashTimes) > i) ? g_processedHashTimes[i] : 0;
      if(seenAt <= 0 || (nowTs - seenAt) > windowSec)
         continue;

      if(writeIdx != i)
      {
         g_processedHashes[writeIdx] = g_processedHashes[i];
         g_processedHashTimes[writeIdx] = seenAt;
      }
      writeIdx++;
   }

   ArrayResize(g_processedHashes, writeIdx);
   ArrayResize(g_processedHashTimes, writeIdx);
}

// -----------------------------------------------------------------------------
// DIAGNOSTIC LOG -- timestamped signal trace file, enabled by EnableDiagLog
// Path: MQL5/Files/ (viewable in MT5 File Manager or Windows Explorer)
// -----------------------------------------------------------------------------
int g_diagFile = INVALID_HANDLE;

void DiagLog(string status, string detail)
{
   if(!EnableDiagLog || g_diagFile == INVALID_HANDLE) return;
   string line = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)
               + " | " + StringFormat("%-10s", status)
               + " | " + detail + "\r\n";
   FileWriteString(g_diagFile, line);
   FileFlush(g_diagFile);   // flush so file is readable even if EA crashes
}
void DiagSep()
{
   if(!EnableDiagLog || g_diagFile == INVALID_HANDLE) return;
   FileWriteString(g_diagFile, "------------------------------------------------------------\r\n");
   FileFlush(g_diagFile);
}
void DiagNew(string raw, string src)
{
   DiagSep();
   DiagLog("IN", "src=" + src + " | \"" + StringSubstr(raw, 0, 120) + "\"");
}
void DiagTrade(string result, string dir, string sym, double lots, double price)
{
   DiagLog(result, dir + " " + sym + " @ " + DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS))
           + " lots=" + DoubleToString(lots, 2));
}

bool TCU_CooldownEnabled()
{
   return SignalCooldownSeconds > 0;
}

void TCU_SetCooldownEnabled(bool on)
{
   if(on)
   {
      int restoreMin = g_signalCooldownRestoreMinutes;
      if(restoreMin <= 0)
         restoreMin = MathMax(1, inp_SignalCooldownMinutes);
      SignalCooldownSeconds = MathMax(1, restoreMin) * 60;
   }
   else
   {
      int curMin = SignalCooldownSeconds / 60;
      if(curMin > 0)
         g_signalCooldownRestoreMinutes = curMin;
      SignalCooldownSeconds = 0;
   }
}

string TCU_ExtractTelegramChatId(string json, int startPos, int textPos)
{
   int chatPos = StringFind(json, "\"chat\":{", startPos);
   if(chatPos < 0 || chatPos > textPos) return "";

   int idPos = StringFind(json, "\"id\":", chatPos);
   if(idPos < 0 || idPos > textPos) return "";

   int valStart = idPos + 5;
   int len = StringLen(json);
   while(valStart < len)
   {
      ushort c = StringGetCharacter(json, valStart);
      if(c == ' ' || c == '\t') { valStart++; continue; }
      break;
   }

   string out = "";
   for(int i = valStart; i < len && i < textPos; i++)
   {
      ushort c = StringGetCharacter(json, i);
      if((c >= '0' && c <= '9') || c == '-')
         out += ShortToString(c);
      else
         break;
   }
   return out;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+

// --- SC State ----------------------------------------------------------------
int    g_scTab=0;
int    g_partialMode=0; // 0=pct, 1=lots
bool   g_scOpen=false;
int    g_scX=250, g_scY=20;
string g_scObjArr[];
int    g_scObjCnt=0;

void _ScTrack(string nm) {
   if(g_scObjCnt>=ArraySize(g_scObjArr)) ArrayResize(g_scObjArr,g_scObjCnt+120);
   g_scObjArr[g_scObjCnt++]=nm;
}
void _ScDeleteAll() {
   for(int i=0;i<g_scObjCnt;i++) ObjectDelete(0,g_scObjArr[i]);
   g_scObjCnt=0; g_scOpen=false; ChartRedraw(0);
}
// Delete only tab content objects (names starting with SC_CB, SC_H, SC_s, SC_r, SC_f, SC_t, SC_p, SC_g)
void _ScDeleteContent() {
   int keep=0;
   for(int i=0;i<g_scObjCnt;i++) {
      string nm=g_scObjArr[i];
      bool isContent=false;
      if(StringFind(nm,SC_PFX+"CB")==0) isContent=true;
      if(StringFind(nm,SC_PFX+"H0")==0 || StringFind(nm,SC_PFX+"H1")==0 ||
         StringFind(nm,SC_PFX+"H2")==0 || StringFind(nm,SC_PFX+"H3")==0 ||
         StringFind(nm,SC_PFX+"H4")==0 || StringFind(nm,SC_PFX+"H5")==0) isContent=true;
      if(StringFind(nm,SC_PFX+"s0")==0 || StringFind(nm,SC_PFX+"r0")==0 ||
         StringFind(nm,SC_PFX+"r1")==0 || StringFind(nm,SC_PFX+"f0")==0 ||
         StringFind(nm,SC_PFX+"f1")==0 || StringFind(nm,SC_PFX+"t0")==0 ||
         StringFind(nm,SC_PFX+"t1")==0 || StringFind(nm,SC_PFX+"p0")==0 ||
         StringFind(nm,SC_PFX+"p1")==0 ||
         StringFind(nm,SC_PFX+"pM")==0 || StringFind(nm,SC_PFX+"g0")==0 ||
         StringFind(nm,SC_PFX+"g1")==0) isContent=true;
      if(isContent) ObjectDelete(0,nm);
      else { g_scObjArr[keep]=nm; keep++; }
   }
   g_scObjCnt=keep;
}

// helpers
void _R(string n,int x,int y,int w,int h,color bg,color bd=clrNONE){
   string nm=SC_PFX+n; _ScTrack(nm);
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,w); ObjectSetInteger(0,nm,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,nm,OBJPROP_COLOR,bd==clrNONE?bg:bd);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}
void _L(string n,int x,int y,string t,color c,int s=8,string f="Segoe UI"){
   string nm=SC_PFX+n; _ScTrack(nm);
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,nm,OBJPROP_TEXT,t); ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetString(0,nm,OBJPROP_FONT,f); ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,s);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}
void _E(string n,int x,int y,int w,string v){
   string nm=SC_PFX+n; _ScTrack(nm);
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_EDIT,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,w); ObjectSetInteger(0,nm,OBJPROP_YSIZE,18);
   ObjectSetString(0,nm,OBJPROP_TEXT,v); ObjectSetInteger(0,nm,OBJPROP_COLOR,SC_TC);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,SC_IBG); ObjectSetInteger(0,nm,OBJPROP_BORDER_COLOR,SC_IBD);
   ObjectSetString(0,nm,OBJPROP_FONT,"Segoe UI"); ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}
void _B(string n,int x,int y,int w,int h,string t,color bg,color fg=clrWhite,int s=8){
   string nm=SC_PFX+n; _ScTrack(nm);
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,w); ObjectSetInteger(0,nm,OBJPROP_YSIZE,h);
   ObjectSetString(0,nm,OBJPROP_TEXT,t); ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,fg); ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,s);
   ObjectSetString(0,nm,OBJPROP_FONT,"Segoe UI Bold");
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_STATE,false);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,5);
}
void _Hdr(string n,int x,int y,int w,string t){
   _R(n+"b",x,y,w,20,SC_HDC);
   _L(n+"l",x+6,y+2,t,SC_SC,8,"Segoe UI Bold");
   _R(n+"d",x,y+19,w,1,SC_DV);
}
void _Row(string n,int x,int y,int w,string lbl,string val,int lw=148){
   _L(n+"l",x+6,y+2,lbl,SC_DC); _E(n+"e",x+lw,y,w-lw-6,val);
}
void _Tog(string n,int x,int y,int w,string lbl,bool on){
   _L(n+"l",x+6,y+2,lbl,SC_DC); _B(n+"b",x+w-55,y,50,18,on?"ON":"OFF",on?SC_OK:SC_NG);
}

// --- SIDEBAR -----------------------------------------------------------------
void _BuildSidebar(){
   int x=g_scX, y=g_scY+30;
   string tabs[]={"SIGNAL","RISK","FILTER","TRADE","STOPS","SYSTEM"};
   int th=38;
   _R("SB",x,y,SC_SIDE,SC_TABS*th+2,SC_SBC);
   _R("SVB",x+SC_SIDE-1,y,1,SC_TABS*th+2,SC_DV);
   for(int i=0;i<SC_TABS;i++){
      bool a=(i==g_scTab); int ny=y+i*th;
      _R("NA"+IntegerToString(i),x+1,ny,3,th,a?SC_AC:SC_SBC);
      // Button IS the visible tab label
      string bn="NB"+IntegerToString(i);
      string nm=SC_PFX+bn; _ScTrack(nm);
      if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x+4);
      ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,ny+1);
      ObjectSetInteger(0,nm,OBJPROP_XSIZE,SC_SIDE-5);
      ObjectSetInteger(0,nm,OBJPROP_YSIZE,th-2);
      ObjectSetString(0,nm,OBJPROP_TEXT,tabs[i]);
      ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,a?SC_NAC:SC_SBC);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,a?SC_AC:SC_DC);
      ObjectSetString(0,nm,OBJPROP_FONT,a?"Segoe UI Bold":"Segoe UI");
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_STATE,false);
      ObjectSetInteger(0,nm,OBJPROP_ZORDER,5);
      if(i<SC_TABS-1) _R("ND"+IntegerToString(i),x+4,ny+th-1,SC_SIDE-8,1,SC_DV);
   }
}

// --- TAB 0: SIGNAL ----------------------------------------------------------
void _Tab0(){
   int x=g_scX+SC_SIDE,w=SC_CW,y=g_scY+30;
   _R("CB",x,y,w,720,SC_BGC); y+=6;
   _Hdr("H00",x,y,w,"TELEGRAM BOT API"); y+=24;
   _Tog("s01",x,y,w,"Enable Bot API",EnableBotAPIMode); y+=SC_RH;
   _Row("s02",x,y,w,"Bot Token",TelegramBotToken,90); y+=SC_RH;
   _Row("s03",x,y,w,"Chat ID",TelegramChatID,90); y+=SC_RH;
   _Row("s04",x,y,w,"Poll Sec",IntegerToString(TelegramPollSeconds)); y+=SC_RH+4;
   _Hdr("H01",x,y,w,"BRIDGE"); y+=24;
   _Tog("s05",x,y,w,"Enable Bridge",EnableBridgeMode); y+=SC_RH;
   _Row("s06",x,y,w,"Port",IntegerToString(BridgePort)); y+=SC_RH;
   _Row("s07",x,y,w,"Poll ms",IntegerToString(BridgePollMs)); y+=SC_RH+4;
   _Hdr("H02",x,y,w,"DISCORD WEBHOOK"); y+=24;
   _Tog("s08",x,y,w,"Enable Discord Send",EnableDiscordMode); y+=SC_RH;
   _Row("s09",x,y,w,"Webhook URL",DiscordWebhookURL,90); y+=SC_RH;
   y+=4;
   _Hdr("H03",x,y,w,"TELEGRAM BROADCAST"); y+=24;
   _Tog("s0B",x,y,w,"Forward Trades",EnableTelegramSend); y+=SC_RH;
   _Row("s0C",x,y,w,"Tag",TelegramSendTag); y+=SC_RH;
   _Tog("s0D",x,y,w,"Sep. Send Bot",UseSeparateSendBot); y+=SC_RH;
   _Row("s0E",x,y,w,"Send Token",SendBotToken,90); y+=SC_RH;
   _Row("s0F",x,y,w,"Send Chat ID",SendChatID,90); y+=SC_RH+4;
}

// --- TAB 1: RISK ------------------------------------------------------------
void _Tab1(){
   int x=g_scX+SC_SIDE,w=SC_CW,y=g_scY+30;
   _R("CB",x,y,w,720,SC_BGC); y+=6;
   _Hdr("H10",x,y,w,"LOT SIZING"); y+=24;
   _L("r01l",x+6,y+2,"Lot Mode",SC_DC); _B("r01b",x+148,y,w-148-6,18,TCU_LotModeText(),C'20,40,55',SC_AC,8); y+=SC_RH;
   _Row("r02",x,y,w,"Fixed Lot",DoubleToString(FixedLotSize,2)); y+=SC_RH;
   _Row("r04",x,y,w,"Risk %",DoubleToString(RiskPercent,1)); y+=SC_RH;
   _Row("r05",x,y,w,"Default SL pts",IntegerToString(DefaultSLPoints)); y+=SC_RH;
   _Row("r06",x,y,w,"Max Lot",DoubleToString(MaxLotSize,2)); y+=SC_RH;
   _Tog("r07",x,y,w,"Skip If > Max Lot",SkipIfLotOverMax); y+=SC_RH+4;
   _Hdr("H11",x,y,w,"CIRCUIT BREAKERS"); y+=24;
   _Row("r08",x,y,w,"Max Trades/min",IntegerToString(MaxTradesPerMinute)); y+=SC_RH;
   _Row("r09",x,y,w,"Max Open Pos",IntegerToString(MaxOpenPositions)); y+=SC_RH;
   _Row("r0A",x,y,w,"Daily Loss %",DoubleToString(MaxDailyLossPercent,1)); y+=SC_RH;
   _Row("r0B",x,y,w,"Daily Loss $",DoubleToString(MaxDailyLossAmount,2)); y+=SC_RH+4;
   _Hdr("H12",x,y,w,"EA-TO-EA COPIER LOTS"); y+=24;
   _L("r0Cl",x+6,y+2,"Copier Mode",SC_DC); _B("r0Cb",x+148,y,w-148-6,18,EnumToString(CopierMode),C'20,40,55',SC_AC,8); y+=SC_RH;
   _Row("r0D",x,y,w,"CSV File",CopierFileName); y+=SC_RH;
   _Tog("r0E",x,y,w,"Auto-Close Slave",CopierAutoClose); y+=SC_RH;
   _Row("r0F",x,y,w,"Poll ms",IntegerToString(CopierPollMs)); y+=SC_RH;
   _L("r0Gl",x+6,y+2,"Startup Copy",SC_DC); _B("r0Gb",x+148,y,w-148-6,18,TCU_CopierStartupModeText(),C'20,40,55',SC_AC,8); y+=SC_RH;
   _L("r10l",x+6,y+2,"Copier Lot Mode",SC_DC); _B("r10b",x+148,y,w-148-6,18,EnumToString(CopierLotMode),C'20,40,55',SC_AC,8); y+=SC_RH;
   _Row("r11",x,y,w,"Copier Fixed",DoubleToString(CopierFixedLot,2)); y+=SC_RH;
   _Row("r12",x,y,w,"Copier Mult",DoubleToString(CopierLotMultiplier,2)); y+=SC_RH;
   _Row("r14",x,y,w,"Min Lot To Copy",DoubleToString(CopierMinimumLotToCopy,2)); y+=SC_RH;
   _L("r15l",x+6,y+2,"Comment Mode",SC_DC); _B("r15b",x+148,y,w-148-6,18,TCU_CopierTradeCommentModeText(),C'20,40,55',SC_AC,8); y+=SC_RH;
   _Row("r16",x,y,w,"Custom Comment",CopierCustomTradeComment); y+=SC_RH;
   _Row("r13",x,y,w,"Copier Max",DoubleToString(CopierMaxLot,2)); y+=SC_RH;
}

// --- TAB 2: FILTER ----------------------------------------------------------
void _Tab2(){
   int x=g_scX+SC_SIDE,w=SC_CW,y=g_scY+30;
   _R("CB",x,y,w,720,SC_BGC); y+=6;
   _Hdr("H20",x,y,w,"SYMBOL FILTERS"); y+=24;
   _Tog("f01",x,y,w,"Whitelist",EnableWhitelist); y+=SC_RH;
   _Row("f02",x,y,w,"Symbols",WhitelistSymbols,80); y+=SC_RH;
   _Tog("f03",x,y,w,"Blacklist",EnableBlacklist); y+=SC_RH;
   _Row("f04",x,y,w,"Symbols",BlacklistSymbols,80); y+=SC_RH+4;
   _Hdr("H21",x,y,w,"KEYWORD FILTERS"); y+=24;
   _Tog("f05",x,y,w,"Skip Keywords",EnableSkipKeywords); y+=SC_RH;
   _Row("f06",x,y,w,"Phrases",SkipKeywords,80); y+=SC_RH;
   _Tog("f07",x,y,w,"Entry Armour",RequireEntryArmour); y+=SC_RH;
   _Tog("f08",x,y,w,"Skip No SL",SkipSignalWithoutSL); y+=SC_RH;
   _Tog("f09",x,y,w,"Skip No TP",SkipSignalWithoutTP); y+=SC_RH+4;
   _Hdr("H22",x,y,w,"TIME & COOLDOWN"); y+=24;
   _Tog("f10",x,y,w,"Time Filter",EnableTimeFilter); y+=SC_RH;
   _Row("f11",x,y,w,"Start Hour",IntegerToString(TimeFilterStartHour)); y+=SC_RH;
   _Row("f12",x,y,w,"End Hour",IntegerToString(TimeFilterEndHour)); y+=SC_RH;
   _Row("f13",x,y,w,"Cooldown min",IntegerToString(SignalCooldownSeconds/60)); y+=SC_RH;

   _Tog("f14",x,y,w,"Allow SLTP in CD",AllowSLTPModDuringCooldown); y+=SC_RH;
   _Row("f15",x,y,w,"Min Pips Same",DoubleToString(MinPipsDistanceSameType,1)); y+=SC_RH;
}

// --- TAB 3: TRADE -----------------------------------------------------------
void _Tab3(){
   int x=g_scX+SC_SIDE,w=SC_CW,y=g_scY+30;
   _R("CB",x,y,w,720,SC_BGC); y+=6;
   _Hdr("H30",x,y,w,"ORDER EXECUTION"); y+=24;
   _Tog("t01",x,y,w,"Pending Orders",EnablePendingOrders); y+=SC_RH;
   _Tog("t02",x,y,w,"Pending Expiry",EnablePendingExpiry); y+=SC_RH;

   _Tog("t03",x,y,w,"Pending Multi-TP",EnablePendingMultiTP); y+=SC_RH;
   _Row("t03h",x,y,w,"Expiry Hours",IntegerToString(PendingExpiryHours)); y+=SC_RH;
   _Tog("t04",x,y,w,"Copy SL",CopySL); y+=SC_RH;
   _Tog("t05",x,y,w,"Copy TP",CopyTP); y+=SC_RH;
   _Tog("t06",x,y,w,"Reverse Signal",ReverseSignal); y+=SC_RH;
   _Row("t07",x,y,w,"Symbol Suffix",SymbolSuffix); y+=SC_RH;
   _Row("t08",x,y,w,"Custom Mappings",CustomMappings,100); y+=SC_RH+4;
   _Hdr("H31",x,y,w,"AUTO SL / TP"); y+=24;
   _Tog("t09",x,y,w,"Auto SL",EnableAutoSL); y+=SC_RH;
   _Row("t0A",x,y,w,"SL Pips",IntegerToString(FallbackSLPips)); y+=SC_RH;
   _Tog("t0B",x,y,w,"Auto TP",EnableAutoTP); y+=SC_RH;
   _Row("t0C",x,y,w,"TP Pips",IntegerToString(FallbackTPPips)); y+=SC_RH+4;
   _Hdr("H32",x,y,w,"COMMANDS & KEYWORDS"); y+=24;
   _Tog("t0D",x,y,w,"Custom SLTP KW",EnableCustomSLTPKeywords); y+=SC_RH;
   _Row("t0E",x,y,w,"SL Keywords",CustomSLKeywords,100); y+=SC_RH;
   _Row("t0F",x,y,w,"TP Keywords",CustomTPKeywords,100); y+=SC_RH;
   _Tog("t10",x,y,w,"React Commands",EnableCommandReplies); y+=SC_RH;
   _Tog("t11",x,y,w,"Replace KW",EnableKeywordReplace); y+=SC_RH;
   _Row("t12",x,y,w,"Replace Map",KeywordReplaceMap,100); y+=SC_RH+4;

}

// --- TAB 4: STOPS -----------------------------------------------------------
void _Tab4(){
   int x=g_scX+SC_SIDE,w=SC_CW,y=g_scY+30;
   _R("CB",x,y,w,720,SC_BGC); y+=6;
   _Hdr("H40",x,y,w,"TRAILING STOP"); y+=24;
   _Tog("p01",x,y,w,"Enable Trailing",EnableTrailingStop); y+=SC_RH;
   _Row("p02",x,y,w,"Start Pips",IntegerToString(TrailStartPips)); y+=SC_RH;
   _Row("p03",x,y,w,"Distance Pips",IntegerToString(TrailDistancePips)); y+=SC_RH;
   _Row("p04",x,y,w,"Step Pips",IntegerToString(TrailStepPips)); y+=SC_RH;
   _Tog("p05",x,y,w,"Move to BE",TrailMoveToBreakeven); y+=SC_RH+4;
   _Hdr("H41",x,y,w,"PARTIAL CLOSE (PIPS-BASED)"); y+=24;
   _Tog("p06",x,y,w,"Enable Partial",EnablePartialClose); y+=SC_RH;
   // Mode selector: LOTS or PERCENT
   _L("pML",x+6,y+2,"Close Mode",SC_DC); _B("pMb",x+148,y,w-148-6,20,PartialCloseMode==PARTIAL_PERCENTAGE?"PERCENTAGE":"FIXED LOTS",C'20,40,55',SC_AC,8); y+=SC_RH+2;
   if(PartialCloseMode==PARTIAL_PERCENTAGE) { // Percentage mode
      _Row("p07",x,y,w,"TP1 Pips",DoubleToString(PartialTP1Pips,1)); y+=SC_RH;
      _Row("p09",x,y,w,"TP1 Close %",DoubleToString(PartialTP1Percent,0)); y+=SC_RH;
      _Row("p0A",x,y,w,"TP2 Pips",DoubleToString(PartialTP2Pips,1)); y+=SC_RH;
      _Row("p0C",x,y,w,"TP2 Close %",DoubleToString(PartialTP2Percent,0)); y+=SC_RH;
      _Row("p0D",x,y,w,"TP3 Pips",DoubleToString(PartialTP3Pips,1)); y+=SC_RH;
      _Row("p0F",x,y,w,"TP3 Close %",DoubleToString(PartialTP3Percent,0)); y+=SC_RH;
   } else { // Fixed lots mode
      _Row("p07",x,y,w,"TP1 Pips",DoubleToString(PartialTP1Pips,1)); y+=SC_RH;
      _Row("p08",x,y,w,"TP1 Lots",DoubleToString(PartialTP1Lots,2)); y+=SC_RH;
      _Row("p0A",x,y,w,"TP2 Pips",DoubleToString(PartialTP2Pips,1)); y+=SC_RH;
      _Row("p0B",x,y,w,"TP2 Lots",DoubleToString(PartialTP2Lots,2)); y+=SC_RH;
      _Row("p0D",x,y,w,"TP3 Pips",DoubleToString(PartialTP3Pips,1)); y+=SC_RH;
      _Row("p0E",x,y,w,"TP3 Lots",DoubleToString(PartialTP3Lots,2)); y+=SC_RH;
   }
   _Tog("p10",x,y,w,"SL to BE at TP1",PartialMoveSLBreakeven); y+=SC_RH;
   _Row("p11",x,y,w,"BE Extra Pips",IntegerToString(PartialBEExtraPips)); y+=SC_RH;
   _Tog("p12",x,y,w,"SL to TP1 at TP2",PartialMoveSLToTP1); y+=SC_RH+4;
   _Hdr("H42",x,y,w,"SIGNAL TP SPLITTING"); y+=24;
   _Tog("p13",x,y,w,"Multi-TP Split",EnableMultiTP); y+=SC_RH;
   _Row("p14",x,y,w,"Max TPs",IntegerToString(MaxTPTargets)); y+=SC_RH;
   _L("pSML",x+6,y+2,"Alloc Mode",SC_DC); _B("pSMb",x+148,y,w-148-6,20,SignalTpAllocMode==PARTIAL_PERCENTAGE?"PERCENTAGE":"FIXED LOTS",C'20,40,55',SC_AC,8); y+=SC_RH+2;
   _Row("p15",x,y,w,SignalTpAllocMode==PARTIAL_FIXED_LOTS?"TP Lots":"Lot Dist %",SignalTpAllocMode==PARTIAL_FIXED_LOTS?SignalTpLotValues:LotDistribution); y+=SC_RH;
   _Tog("p16",x,y,w,"SL->BE on TP1",TGMoveSLBreakevenTP1); y+=SC_RH;
   _Tog("p17",x,y,w,"SL->TP1 on TP2",TGMoveSLToTP1OnTP2); y+=SC_RH;
   _Row("p18",x,y,w,"BE Extra Pips",IntegerToString(TGBreakevenExtraPips)); y+=SC_RH;
}

// --- TAB 5: SYSTEM ----------------------------------------------------------
void _Tab5(){
   int x=g_scX+SC_SIDE,w=SC_CW,y=g_scY+30;
   _R("CB",x,y,w,720,SC_BGC); y+=6;
   _Hdr("H50",x,y,w,"SAFETY PROFILE"); y+=24;
   _Tog("g01",x,y,w,"ARM Execution",ArmExecution); y+=SC_RH;
   _Tog("g02",x,y,w,"Duplicate Filter",EnableDuplicateFilter); y+=SC_RH;
   _Row("g02h",x,y,w,"Dup Window min",IntegerToString(DuplicateWindowMinutes)); y+=SC_RH;
   _Tog("g03",x,y,w,"Prop Firm Mode",PropFirmMode); y+=SC_RH;
   _Tog("g05",x,y,w,"Diag Log",EnableDiagLog); y+=SC_RH;
   _Row("g06",x,y,w,"Magic Number",IntegerToString(MagicNumber)); y+=SC_RH+4;
   _Hdr("H51",x,y,w,"SPREAD & SLIPPAGE"); y+=24;
   _Tog("g07",x,y,w,"Spread Filter",EnableSpreadFilter); y+=SC_RH;
   _Row("g08",x,y,w,"Max Spread pts",IntegerToString(MaxSpreadPoints)); y+=SC_RH;
   _Tog("g09",x,y,w,"Slippage Filter",EnableSlippageFilter); y+=SC_RH;
   _Row("g0A",x,y,w,"Slippage pts",IntegerToString(SlippagePoints)); y+=SC_RH;
   _Row("g0B",x,y,w,"Entry Slip pips",DoubleToString(EntrySlippagePips,1)); y+=SC_RH;
   _L("g0Cl",x+6,y+2,"Slip Action",SC_DC); _B("g0Cb",x+148,y,w-148-6,18,EnumToString(SlippageAction),C'20,40,55',SC_AC,8); y+=SC_RH;
   _Row("g0D",x,y,w,"Opposite Action",EnumToString(OppositeAction)); y+=SC_RH+4;
   _Hdr("H52",x,y,w,"ALERTS"); y+=24;
   _Tog("g0E",x,y,w,"Popup Alerts",EnablePopupAlerts); y+=SC_RH;
   _Tog("g0F",x,y,w,"Sound Alerts",EnableSoundAlerts); y+=SC_RH;
   _Tog("g10",x,y,w,"Push Notify",EnablePushNotify); y+=SC_RH;
   _Tog("g10A",x,y,w,"Partial Alerts",EnablePartialAlerts); y+=SC_RH;
   _Row("g11",x,y,w,"Sound File",AlertSoundFile); y+=SC_RH+4;
   _Hdr("H53",x,y,w,"REPORT"); y+=24;
   _Tog("g12",x,y,w,"Report Log",EnableReportLog); y+=SC_RH;
   _Row("g13",x,y,w,"Purge Days",IntegerToString(ReportPurgeDays)); y+=SC_RH;
}

// --- SHOW/CLOSE --------------------------------------------------------------

// --- ENUM CYCLING ------------------------------------------------------------
void TCU_SetCopierStateFileName()
{
   if(CopierMode == MODE_DISABLED)
   {
      g_stateFileName = "";
      return;
   }
   long acctLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   g_stateFileName = "TCU_State_" + IntegerToString(acctLogin) + "_" +
                     IntegerToString(MagicNumber) + "_" + CopierFileName;
   StringReplace(g_stateFileName, ".csv", ".dat");
}

void TCU_ReinitializeSlaveCopierState()
{
   ArrayResize(g_copiedTickets, 0);
   ArrayResize(g_masterTicketMap, 0);
   ArrayResize(g_slaveTickets, 0);
   ArrayResize(g_masterLots, 0);
   g_initialSyncDone = (CopierStartupCopyMode == COPY_ALL_EXISTING_TRADES);
   g_initialSyncEmptyReadableScans = 0;
   g_initialSyncSnapshotCount = -1;
   g_initialSyncSnapshotHash = 0;
   g_slaveActivationGuardUntil = (CopierStartupCopyMode == COPY_NEW_TRADES_ONLY)
                                  ? GetTickCount64() + (ulong)g_slaveActivationGuardMs
                                  : 0;
   g_emptyReadCount = 0;
   g_scanInProgress = false;
   g_lastFileScan = 0;
   if(CopierStartupCopyMode == COPY_NEW_TRADES_ONLY)
      LoadSlaveState();
   Print("[SLAVE] Live mode switch -> SLAVE: startup mode=", EnumToString(CopierStartupCopyMode),
         " activation guard=", (CopierStartupCopyMode == COPY_NEW_TRADES_ONLY ? g_slaveActivationGuardMs : 0),
         "ms. Tracked trades from previous session: ", ArraySize(g_masterTicketMap));
}

void TCU_MasterActivate()
{
   if(CopierStartupCopyMode == COPY_NEW_TRADES_ONLY)
   {
      g_masterActivationTime = TimeCurrent();
      g_masterActivationBaselineUntil = GetTickCount64() + (ulong)g_masterActivationBaselineMs;
      Print("[MASTER] Activation baseline active. Positions already open now will be published as baseline/non-copyable.");
   }
   else
   {
      g_masterActivationTime = 0;
      g_masterActivationBaselineUntil = 0;
      Print("[MASTER] Startup mode COPY_ALL_EXISTING_TRADES - current positions are copyable.");
   }
}

void TCU_HandleCopierModeTransition(ENUM_COPIER_MODE oldMode, ENUM_COPIER_MODE newMode)
{
   if(oldMode == newMode)
      return;

   if(oldMode == MODE_SLAVE && newMode != MODE_SLAVE)
      SaveSlaveState();

   CopierMode = newMode;
   TCU_SetCopierStateFileName();

   if(newMode == MODE_SLAVE)
   {
      TCU_ReinitializeSlaveCopierState();
   }
   else
   {
      g_scanInProgress = false;
      g_lastFileScan = 0;
      if(newMode == MODE_MASTER)
      {
         TCU_MasterActivate();
         WriteMasterTrades();
      }
   }
}

void TCU_RegisterSlaveBaselineTrade(ulong masterTicket, string typeStr, string sym, double masterLots, string reportTag, string note)
{
   Print("[SLAVE] ", note, " #", masterTicket, " ", typeStr, " ", sym, " without copying");
   WriteReport(reportTag, sym, typeStr, masterLots, masterTicket, 0, "registered without copying");

   int idx2 = ArraySize(g_copiedTickets);
   ArrayResize(g_copiedTickets, idx2 + 1);
   g_copiedTickets[idx2] = masterTicket;

   string slaveDir = typeStr;
   if(ReverseSignal)
   {
      if(slaveDir == "BUY") slaveDir = "SELL";
      else if(slaveDir == "SELL") slaveDir = "BUY";
   }

   ulong existingTicket = SlaveHasPosition(sym, slaveDir);
   if(existingTicket > 0)
   {
      Print("[SLAVE] Linking existing slave #", existingTicket, " to master #", masterTicket);
      int mapIdx2 = ArraySize(g_masterTicketMap);
      ArrayResize(g_masterTicketMap, mapIdx2 + 1);
      ArrayResize(g_slaveTickets, mapIdx2 + 1);
      ArrayResize(g_masterLots, mapIdx2 + 1);
      g_masterTicketMap[mapIdx2] = masterTicket;
      g_slaveTickets[mapIdx2] = existingTicket;
      g_masterLots[mapIdx2] = masterLots;
   }
}

bool TCU_RestoreSlaveMapForMaster(ulong masterTicket, string sym, string masterTypeStr, double masterLots)
{
   string slaveDir = masterTypeStr;
   if(ReverseSignal)
   {
      if(slaveDir == "BUY") slaveDir = "SELL";
      else if(slaveDir == "SELL") slaveDir = "BUY";
   }

   ulong relinkTicket = SlaveHasPosition(sym, slaveDir);
   if(relinkTicket == 0)
      return false;

   int existingIdx = -1;
   int mapSz = ArraySize(g_masterTicketMap);
   for(int i = 0; i < mapSz; i++)
   {
      if(g_masterTicketMap[i] == masterTicket)
      {
         existingIdx = i;
         break;
      }
   }

   int mapIdx = existingIdx;
   if(mapIdx < 0)
   {
      mapIdx = mapSz;
      ArrayResize(g_masterTicketMap, mapIdx + 1);
      ArrayResize(g_slaveTickets, mapIdx + 1);
      ArrayResize(g_masterLots, mapIdx + 1);
      g_masterTicketMap[mapIdx] = masterTicket;
   }
   else if(mapIdx >= ArraySize(g_masterLots))
   {
      ArrayResize(g_masterLots, mapIdx + 1);
   }

   g_slaveTickets[mapIdx] = relinkTicket;
   g_masterLots[mapIdx] = masterLots;
   SaveSlaveState();
   Print("[SLAVE] Restored live map: master #", masterTicket, " -> slave #", relinkTicket,
         " (", sym, " ", slaveDir, ")");
   return true;
}

void _Cycle_CopierMode()
{
   ENUM_COPIER_MODE oldMode = CopierMode;
   ENUM_COPIER_MODE newMode = (ENUM_COPIER_MODE)(((int)CopierMode + 1) % 3);
   TCU_HandleCopierModeTransition(oldMode, newMode);
}
void _Cycle_CopierLotMode(){ CopierLotMode=(ENUM_COPIER_LOT_MODE)(((int)CopierLotMode+1)%5); }
void _Cycle_CopierTradeCommentMode(){ CopierTradeCommentMode=(ENUM_TRADE_COMMENT_MODE)(((int)CopierTradeCommentMode+1)%3); }
void _Cycle_CopierStartupCopyMode(){ CopierStartupCopyMode=(CopierStartupCopyMode==COPY_NEW_TRADES_ONLY ? COPY_ALL_EXISTING_TRADES : COPY_NEW_TRADES_ONLY); }
void _Cycle_LotMode(){ LotMode=(LotMode==LOT_FIXED)?LOT_RISK_PERCENT:LOT_FIXED; }
void _Cycle_PanelMode(){ PanelMode=(ENUM_PANEL_MODE)(((int)PanelMode+1)%2); }
void _Cycle_PartialScope(){ PartialScope=(ENUM_PARTIAL_SCOPE)(((int)PartialScope+1)%2); }
void _Cycle_SlippageAction(){ SlippageAction=(ENUM_SLIPPAGE_ACTION)(((int)SlippageAction+1)%2); }
void _Cycle_OppositeAction(){ OppositeAction=(ENUM_OPPOSITE_ACTION)(((int)OppositeAction+1)%3); }


// --- READ ALL EDIT FIELDS INTO SHADOW VARS ----------------------------------
string _GetEdit(string n) {
   string nm=SC_PFX+n+"e";
   if(ObjectFind(0,nm)>=0) return ObjectGetString(0,nm,OBJPROP_TEXT);
   return "";
}
void _ApplyEdits() {
   string v;
   // -- SIGNAL TAB --
   v=_GetEdit("s02"); if(v!="") TelegramBotToken=v;
   v=_GetEdit("s03"); if(v!="") TelegramChatID=v;
   v=_GetEdit("s04"); if(v!="") TelegramPollSeconds=(int)StringToInteger(v);
   v=_GetEdit("s06"); if(v!="") BridgePort=(int)StringToInteger(v);
   v=_GetEdit("s07"); if(v!="") BridgePollMs=(int)StringToInteger(v);
   v=_GetEdit("s09"); if(v!="") DiscordWebhookURL=v;
   v=_GetEdit("s0A"); if(v!="") DiscordPollSeconds=(int)StringToInteger(v);
   v=_GetEdit("s0C"); if(v!="") TelegramSendTag=v;
   v=_GetEdit("s0E"); if(v!="") SendBotToken=v;
   v=_GetEdit("s0F"); if(v!="") SendChatID=v;

   // -- RISK TAB --
   v=_GetEdit("r02"); if(v!="") FixedLotSize=StringToDouble(v);
   v=_GetEdit("r04"); if(v!="") RiskPercent=StringToDouble(v);
   v=_GetEdit("r05"); if(v!="") DefaultSLPoints=(int)StringToInteger(v);
   v=_GetEdit("r06"); if(v!="") MaxLotSize=StringToDouble(v);
   v=_GetEdit("r08"); if(v!="") MaxTradesPerMinute=(int)StringToInteger(v);
   v=_GetEdit("r09"); if(v!="") MaxOpenPositions=(int)StringToInteger(v);
   v=_GetEdit("r0A"); if(v!="") MaxDailyLossPercent=StringToDouble(v);
   v=_GetEdit("r0B"); if(v!="") MaxDailyLossAmount=StringToDouble(v);
   v=_GetEdit("r0D"); if(v!="") CopierFileName=v;
   v=_GetEdit("r0F"); if(v!="") CopierPollMs=(int)StringToInteger(v);
   v=_GetEdit("r11"); if(v!="") CopierFixedLot=StringToDouble(v);
   v=_GetEdit("r12"); if(v!="") CopierLotMultiplier=StringToDouble(v);
   v=_GetEdit("r13"); if(v!="") CopierMaxLot=StringToDouble(v);
   v=_GetEdit("r14"); if(v!="") CopierMinimumLotToCopy=MathMax(0.0,StringToDouble(v));
   v=_GetEdit("r16"); if(v!="") CopierCustomTradeComment=v;

   // -- FILTER TAB --
   v=_GetEdit("f02"); WhitelistSymbols=v;
   v=_GetEdit("f04"); BlacklistSymbols=v;
   v=_GetEdit("f06"); SkipKeywords=v;
   v=_GetEdit("f11"); if(v!="") TimeFilterStartHour=(int)StringToInteger(v);
   v=_GetEdit("f12"); if(v!="") TimeFilterEndHour=(int)StringToInteger(v);
   v=_GetEdit("f13"); if(v!="") SignalCooldownSeconds=(int)StringToInteger(v)*60;
   v=_GetEdit("f16"); if(v!="") DuplicateWindowMinutes=MathMax(1,(int)StringToInteger(v));
   v=_GetEdit("f15"); if(v!="") MinPipsDistanceSameType=StringToDouble(v);

   // -- TRADE TAB --
   v=_GetEdit("t03h"); if(v!="") PendingExpiryHours=(int)StringToInteger(v);
   v=_GetEdit("t07"); SymbolSuffix=v;
   v=_GetEdit("t08"); CustomMappings=v;
   v=_GetEdit("t0A"); if(v!="") FallbackSLPips=(int)StringToInteger(v);
   v=_GetEdit("t0C"); if(v!="") FallbackTPPips=(int)StringToInteger(v);
   v=_GetEdit("t0E"); CustomSLKeywords=v;
   v=_GetEdit("t0F"); CustomTPKeywords=v;
   v=_GetEdit("t12"); KeywordReplaceMap=v;

   // -- STOPS TAB --
   v=_GetEdit("p02"); if(v!="") TrailStartPips=(int)StringToInteger(v);
   v=_GetEdit("p03"); if(v!="") TrailDistancePips=(int)StringToInteger(v);
   v=_GetEdit("p04"); if(v!="") TrailStepPips=(int)StringToInteger(v);
   v=_GetEdit("p07"); if(v!="") PartialTP1Pips=StringToDouble(v);
   v=_GetEdit("p08"); if(v!="") { if(PartialCloseMode==PARTIAL_FIXED_LOTS) PartialTP1Lots=StringToDouble(v); }
   v=_GetEdit("p09"); if(v!="") { if(PartialCloseMode==PARTIAL_PERCENTAGE) PartialTP1Percent=StringToDouble(v); }
   v=_GetEdit("p0A"); if(v!="") PartialTP2Pips=StringToDouble(v);
   v=_GetEdit("p0B"); if(v!="") { if(PartialCloseMode==PARTIAL_FIXED_LOTS) PartialTP2Lots=StringToDouble(v); }
   v=_GetEdit("p0C"); if(v!="") { if(PartialCloseMode==PARTIAL_PERCENTAGE) PartialTP2Percent=StringToDouble(v); }
   v=_GetEdit("p0D"); if(v!="") PartialTP3Pips=StringToDouble(v);
   v=_GetEdit("p0E"); if(v!="") { if(PartialCloseMode==PARTIAL_FIXED_LOTS) PartialTP3Lots=StringToDouble(v); }
   v=_GetEdit("p0F"); if(v!="") { if(PartialCloseMode==PARTIAL_PERCENTAGE) PartialTP3Percent=StringToDouble(v); }
   v=_GetEdit("p11"); if(v!="") PartialBEExtraPips=(int)StringToInteger(v);
   v=_GetEdit("p14"); if(v!="") MaxTPTargets=(int)StringToInteger(v);
   v=_GetEdit("p15"); if(v!="") { if(SignalTpAllocMode==PARTIAL_FIXED_LOTS) SignalTpLotValues=v; else LotDistribution=v; }
   v=_GetEdit("p18"); if(v!="") TGBreakevenExtraPips=(int)StringToInteger(v);

   // -- SYSTEM TAB --
   v=_GetEdit("g06"); if(v!="") MagicNumber=(int)StringToInteger(v);
   v=_GetEdit("g02h"); if(v!="") DuplicateWindowMinutes=MathMax(1,(int)StringToInteger(v));
   v=_GetEdit("g08"); if(v!="") MaxSpreadPoints=(int)StringToInteger(v);
   v=_GetEdit("g0A"); if(v!="") SlippagePoints=(int)StringToInteger(v);
   v=_GetEdit("g0B"); if(v!="") EntrySlippagePips=StringToDouble(v);
   v=_GetEdit("g11"); if(v!="") AlertSoundFile=v;
   v=_GetEdit("g13"); if(v!="") ReportPurgeDays=(int)StringToInteger(v);

   Print("[TCU] Settings applied from panel.");
}


//+------------------------------------------------------------------+
// SETTINGS PERSISTENCE: Save/Load panel settings via GlobalVariables
// Survives MT5 restarts. Prefix "TCU_" + MagicNumber avoids conflicts.
//+------------------------------------------------------------------+

// ─── STRING SETTINGS PERSISTENCE (file-based, GlobalVar can only store doubles) ───
string _CfgFile() { return "TCU_" + IntegerToString(MagicNumber) + "_strings.cfg"; }

string TCU_BoolSig(bool v) { return v ? "1" : "0"; }
string TCU_DblSig(double v) { return DoubleToString(v, 8); }

string TCU_CurrentInputSignature()
{
   string s = "";
   s += TCU_BoolSig(inp_EnableBotAPIMode) + "|" + inp_TelegramBotToken + "|" + inp_TelegramChatID + "|";
   s += IntegerToString(inp_TelegramPollSeconds) + "|" + TCU_BoolSig(inp_EnableBridgeMode) + "|" +
        IntegerToString(inp_BridgePort) + "|" + IntegerToString(inp_BridgePollMs) + "|" + inp_AllowedBridgeSources + "|";
   s += TCU_BoolSig(inp_EnableDiscordMode) + "|" + inp_DiscordWebhookURL + "|" + IntegerToString(inp_DiscordPollSeconds) + "|";
   s += IntegerToString((int)inp_CopierMode) + "|" + inp_CopierFileName + "|" + TCU_BoolSig(inp_CopierAutoClose) + "|" +
        IntegerToString(inp_CopierPollMs) + "|" + IntegerToString((int)inp_CopierStartupCopyMode) + "|" +
        IntegerToString((int)inp_CopierLotMode) + "|";
   s += TCU_DblSig(inp_CopierFixedLot) + "|" + TCU_DblSig(inp_CopierLotMultiplier) + "|" +
        TCU_DblSig(inp_CopierRiskPercent) + "|" + TCU_DblSig(inp_CopierMaxLot) + "|" +
        TCU_DblSig(inp_CopierMinimumLotToCopy) + "|" + IntegerToString((int)inp_CopierTradeCommentMode) + "|" +
        inp_CopierCustomTradeComment + "|";
   s += TCU_BoolSig(inp_EnableTelegramSend) + "|" + inp_TelegramSendTag + "|" + inp_TelegramSendSuffix + "|" +
        TCU_BoolSig(inp_UseSeparateSendBot) + "|" + inp_SendBotToken + "|" + inp_SendChatID + "|";
   s += IntegerToString((int)inp_LotMode) + "|" + TCU_DblSig(inp_FixedLotSize) + "|" +
        TCU_DblSig(inp_LotMultiplier) + "|" + TCU_DblSig(inp_RiskPercent) + "|" +
        inp_PerSymbolLots + "|" +  // [v6.00 NEW][PerSymbolLots]
        IntegerToString(inp_DefaultSLPoints) + "|" + TCU_DblSig(inp_MaxLotSize) + "|" +
        TCU_BoolSig(inp_SkipIfLotOverMax) + "|";
   s += IntegerToString(inp_MaxTradesPerMinute) + "|" + IntegerToString(inp_MaxOpenPositions) + "|" +
        TCU_DblSig(inp_MaxDailyLossPercent) + "|" + TCU_DblSig(inp_MaxDailyLossAmount) + "|";
   s += TCU_BoolSig(inp_SkipSignalWithoutSL) + "|" + TCU_BoolSig(inp_SkipSignalWithoutTP) + "|" +
        TCU_BoolSig(inp_EnableSignalTP) + "|" + TCU_BoolSig(inp_EnableAutoSL) + "|" +
        IntegerToString(inp_FallbackSLPips) + "|" + TCU_BoolSig(inp_EnableAutoTP) + "|" +
        IntegerToString(inp_FallbackTPPips) + "|";
   s += TCU_BoolSig(inp_EnableTimeFilter) + "|" + IntegerToString(inp_TimeFilterStartHour) + "|" +
        IntegerToString(inp_TimeFilterEndHour) + "|" + IntegerToString(inp_SignalCooldownMinutes) + "|" +
        TCU_BoolSig(inp_AllowSLTPModDuringCooldown) + "|" + TCU_DblSig(inp_MinPipsDistanceSameType) + "|";
   s += TCU_BoolSig(inp_EnableWhitelist) + "|" + inp_WhitelistSymbols + "|" +
        TCU_BoolSig(inp_EnableBlacklist) + "|" + inp_BlacklistSymbols + "|" +
        TCU_BoolSig(inp_EnableSkipKeywords) + "|" + inp_SkipKeywords + "|";
   s += TCU_BoolSig(inp_EnablePendingOrders) + "|" + TCU_BoolSig(inp_EnablePendingExpiry) + "|" +
        TCU_BoolSig(inp_EnablePendingMultiTP) + "|" + IntegerToString(inp_PendingExpiryHours) + "|";
   s += TCU_BoolSig(inp_RequireEntryArmour) + "|" + TCU_BoolSig(inp_ModifySLTPIfPositionExists) + "|" +
        TCU_BoolSig(inp_CopySL) + "|" + TCU_BoolSig(inp_CopyTP) + "|" + TCU_BoolSig(inp_ReverseSignal) + "|";
   s += inp_SymbolSuffix + "|" + inp_CustomMappings + "|" + TCU_BoolSig(inp_EnableCustomSLTPKeywords) + "|" +
        inp_CustomSLKeywords + "|" + inp_CustomTPKeywords + "|";
   s += TCU_BoolSig(inp_EnableCommandReplies) + "|" + inp_MoveSLCommands + "|" + inp_CloseAllCommands + "|" +
        TCU_BoolSig(inp_EnableKeywordReplace) + "|" + inp_KeywordReplaceMap + "|";
   s += TCU_BoolSig(inp_EnableTrailingStop) + "|" + IntegerToString(inp_TrailStartPips) + "|" +
        IntegerToString(inp_TrailDistancePips) + "|" + IntegerToString(inp_TrailStepPips) + "|" +
        TCU_BoolSig(inp_TrailMoveToBreakeven) + "|" + IntegerToString(inp_BreakevenBufferPips) + "|";
   s += IntegerToString((int)inp_PartialCloseMode) + "|" + TCU_BoolSig(inp_EnablePartialClose) + "|" +
        IntegerToString((int)inp_PartialScope) + "|" +
        TCU_DblSig(inp_PartialTP1Pips) + "|" + TCU_DblSig(inp_PartialTP1Lots) + "|" + TCU_DblSig(inp_PartialTP1Percent) + "|" +
        TCU_DblSig(inp_PartialTP2Pips) + "|" + TCU_DblSig(inp_PartialTP2Lots) + "|" + TCU_DblSig(inp_PartialTP2Percent) + "|" +
        TCU_DblSig(inp_PartialTP3Pips) + "|" + TCU_DblSig(inp_PartialTP3Lots) + "|" + TCU_DblSig(inp_PartialTP3Percent) + "|" +
        TCU_DblSig(inp_PartialTP4Pips) + "|" + TCU_DblSig(inp_PartialTP4Lots) + "|" + TCU_DblSig(inp_PartialTP4Percent) + "|";
   s += TCU_BoolSig(inp_PartialMoveSLBreakeven) + "|" + IntegerToString(inp_PartialBEExtraPips) + "|" +
        TCU_BoolSig(inp_PartialMoveSLToTP1) + "|" + TCU_BoolSig(inp_PartialMoveSLToTP2) + "|" +
        TCU_BoolSig(inp_PartialMoveSLToTP3) + "|";
   s += TCU_BoolSig(inp_EnableMultiTP) + "|" + IntegerToString(inp_MaxTPTargets) + "|" +
        TCU_BoolSig(inp_SignalTpFixedOverrideMainLots) + "|" +
        IntegerToString((int)inp_SignalTpAllocMode) + "|" + inp_LotDistribution + "|" + inp_SignalTpLotValues + "|" +
        TCU_BoolSig(inp_TGMoveSLBreakevenTP1) + "|" + TCU_BoolSig(inp_TGMoveSLToTP1OnTP2) + "|" +
        IntegerToString(inp_TGBreakevenExtraPips) + "|";
   s += TCU_BoolSig(inp_ArmExecution) + "|" + TCU_BoolSig(inp_EnableDuplicateFilter) + "|" + IntegerToString(inp_DuplicateWindowMinutes) + "|" +
        TCU_BoolSig(inp_PropFirmMode) + "|" +
        TCU_BoolSig(inp_EnableDiagLog) + "|" + inp_DiagLogFileName + "|";
   s += TCU_BoolSig(inp_EnableNewsPause) + "|" + IntegerToString(inp_NewsPauseBeforeMinutes) + "|" +
        IntegerToString(inp_NewsPauseAfterMinutes) + "|" + TCU_BoolSig(inp_NewsPauseHighImpact) + "|" +
        TCU_BoolSig(inp_NewsPauseMediumImpact) + "|" + inp_NewsPauseCurrencies + "|";
   s += IntegerToString(inp_MagicNumber) + "|" + IntegerToString((int)inp_PanelMode) + "|" +
        IntegerToString(inp_PanelX) + "|" + IntegerToString(inp_PanelY) + "|";
   s += TCU_BoolSig(inp_EnableSpreadFilter) + "|" + IntegerToString(inp_MaxSpreadPoints) + "|" +
        TCU_BoolSig(inp_EnableSlippageFilter) + "|" + IntegerToString(inp_SlippagePoints) + "|" +
        TCU_DblSig(inp_EntrySlippagePips) + "|" + IntegerToString((int)inp_SlippageAction) + "|" +
        IntegerToString((int)inp_OppositeAction) + "|";
   s += TCU_BoolSig(inp_EnablePopupAlerts) + "|" + TCU_BoolSig(inp_EnableSoundAlerts) + "|" +
        TCU_BoolSig(inp_EnablePushNotify) + "|" + TCU_BoolSig(inp_EnablePartialAlerts) + "|" + inp_AlertSoundFile;
   return s;
}

string TCU_LoadSavedInputSignature()
{
   string fn = _CfgFile();
   if(!FileIsExist(fn, FILE_COMMON)) return "";
   int h = FileOpen(fn, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return "";
   string sig = "";
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringFind(line, "InputSignature=") == 0)
      {
         sig = StringSubstr(line, StringLen("InputSignature="));
         break;
      }
   }
   FileClose(h);
   return sig;
}

string TCU_CurrentStringSettingsState()
{
   string s = TCU_CurrentInputSignature() + "|";
   s += TelegramBotToken + "|" + TelegramChatID + "|" + AllowedBridgeSources + "|" + DiscordWebhookURL + "|";
   s += SymbolSuffix + "|" + CustomMappings + "|" + TelegramSendTag + "|" + TelegramSendSuffix + "|";
   s += SendBotToken + "|" + SendChatID + "|" + CopierFileName + "|" + CopierCustomTradeComment + "|" + CustomSLKeywords + "|" + CustomTPKeywords + "|";
   s += MoveSLCommands + "|" + CloseAllCommands + "|" + SkipKeywords + "|" + KeywordReplaceMap + "|";
   s += LotDistribution + "|" + SignalTpLotValues + "|" + WhitelistSymbols + "|" + BlacklistSymbols + "|" + NewsPauseCurrencies + "|";
   s += DiagLogFileName + "|" + AlertSoundFile + "|";
   s += PerSymbolLots + "|" + MGPerSymbolLots;  // [v6.00 NEW][PerSymbolLots] runtime-edited strings captured for change detection.
   return s;
}

string g_tcuProfileName      = "MyProfile";
string g_tcuProfileStatus    = "";
ulong  g_tcuProfileStatusAt  = 0;
bool   g_tcuProfileOpen      = false;

void TCU_ExportProfile(string name)
{
   StringTrimLeft(name); StringTrimRight(name);
   if(StringLen(name) == 0) name = "MyProfile";
   StringReplace(name, "/", "_"); StringReplace(name, "\\", "_"); StringReplace(name, ":", "_");
   string fn = "TCU_Profile_" + name + ".cfg";
   int h = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) { g_tcuProfileStatus = "ERROR: cannot write " + fn; g_tcuProfileStatusAt = GetTickCount64(); return; }
   FileWriteString(h, "# TCU Settings Profile: " + name + "\n");
   FileWriteString(h, "ArmExecution=" + (ArmExecution ? "1" : "0") + "\n");
   FileWriteString(h, "DisarmOnRestart=" + (DisarmOnRestart ? "1" : "0") + "\n");
   FileWriteString(h, "EnableBridgeMode=" + (EnableBridgeMode ? "1" : "0") + "\n");
   FileWriteString(h, "EnableBotAPIMode=" + (EnableBotAPIMode ? "1" : "0") + "\n");
   FileWriteString(h, "EnableDiscordMode=" + (EnableDiscordMode ? "1" : "0") + "\n");
   FileWriteString(h, "CopierMode=" + IntegerToString((int)CopierMode) + "\n");
   FileWriteString(h, "CopierAutoClose=" + (CopierAutoClose ? "1" : "0") + "\n");
   FileWriteString(h, "EnableReportLog=" + (EnableReportLog ? "1" : "0") + "\n");
   FileWriteString(h, "EnableTelegramSend=" + (EnableTelegramSend ? "1" : "0") + "\n");
   FileWriteString(h, "UseSeparateSendBot=" + (UseSeparateSendBot ? "1" : "0") + "\n");
   FileWriteString(h, "CopySL=" + (CopySL ? "1" : "0") + "\n");
   FileWriteString(h, "CopyTP=" + (CopyTP ? "1" : "0") + "\n");
   FileWriteString(h, "ReverseSignal=" + (ReverseSignal ? "1" : "0") + "\n");
   FileWriteString(h, "EnableMultiTP=" + (EnableMultiTP ? "1" : "0") + "\n");
   FileWriteString(h, "EnablePendingOrders=" + (EnablePendingOrders ? "1" : "0") + "\n");
   FileWriteString(h, "EnablePendingExpiry=" + (EnablePendingExpiry ? "1" : "0") + "\n");
   FileWriteString(h, "EnablePendingMultiTP=" + (EnablePendingMultiTP ? "1" : "0") + "\n");
   FileWriteString(h, "EnableDuplicateFilter=" + (EnableDuplicateFilter ? "1" : "0") + "\n");
   FileWriteString(h, "DuplicateWindowMinutes=" + IntegerToString(DuplicateWindowMinutes) + "\n");
   FileWriteString(h, "EnableTrailingStop=" + (EnableTrailingStop ? "1" : "0") + "\n");
   FileWriteString(h, "EnablePartialClose=" + (EnablePartialClose ? "1" : "0") + "\n");
   FileWriteString(h, "EnableAutoSL=" + (EnableAutoSL ? "1" : "0") + "\n");
   FileWriteString(h, "EnableAutoTP=" + (EnableAutoTP ? "1" : "0") + "\n");
   FileWriteString(h, "EnableNewsPause=" + (EnableNewsPause ? "1" : "0") + "\n");
   FileWriteString(h, "NewsPauseHighImpact=" + (NewsPauseHighImpact ? "1" : "0") + "\n");
   FileWriteString(h, "NewsPauseMediumImpact=" + (NewsPauseMediumImpact ? "1" : "0") + "\n");
   FileWriteString(h, "EnableWhitelist=" + (EnableWhitelist ? "1" : "0") + "\n");
   FileWriteString(h, "EnableBlacklist=" + (EnableBlacklist ? "1" : "0") + "\n");
   FileWriteString(h, "EnableSkipKeywords=" + (EnableSkipKeywords ? "1" : "0") + "\n");
   FileWriteString(h, "EnableTimeFilter=" + (EnableTimeFilter ? "1" : "0") + "\n");
   FileWriteString(h, "EnableSpreadFilter=" + (EnableSpreadFilter ? "1" : "0") + "\n");
   FileWriteString(h, "EnableSlippageFilter=" + (EnableSlippageFilter ? "1" : "0") + "\n");
   FileWriteString(h, "RequireEntryArmour=" + (RequireEntryArmour ? "1" : "0") + "\n");
   FileWriteString(h, "ModifySLTPIfPositionExists=" + (ModifySLTPIfPositionExists ? "1" : "0") + "\n");
   FileWriteString(h, "SkipSignalWithoutSL=" + (SkipSignalWithoutSL ? "1" : "0") + "\n");
   FileWriteString(h, "SkipSignalWithoutTP=" + (SkipSignalWithoutTP ? "1" : "0") + "\n");
   FileWriteString(h, "EnableSignalTP=" + (EnableSignalTP ? "1" : "0") + "\n");
   FileWriteString(h, "AllowSLTPModDuringCooldown=" + (AllowSLTPModDuringCooldown ? "1" : "0") + "\n");
   FileWriteString(h, "EnableCommandReplies=" + (EnableCommandReplies ? "1" : "0") + "\n");
   FileWriteString(h, "EnableKeywordReplace=" + (EnableKeywordReplace ? "1" : "0") + "\n");
   FileWriteString(h, "EnableCustomSLTPKeywords=" + (EnableCustomSLTPKeywords ? "1" : "0") + "\n");
   FileWriteString(h, "EnablePartialAlerts=" + (EnablePartialAlerts ? "1" : "0") + "\n");
   FileWriteString(h, "PartialMoveSLBreakeven=" + (PartialMoveSLBreakeven ? "1" : "0") + "\n");
   FileWriteString(h, "PartialMoveSLToTP1=" + (PartialMoveSLToTP1 ? "1" : "0") + "\n");
   FileWriteString(h, "PartialMoveSLToTP2=" + (PartialMoveSLToTP2 ? "1" : "0") + "\n");
   FileWriteString(h, "PartialMoveSLToTP3=" + (PartialMoveSLToTP3 ? "1" : "0") + "\n");
   FileWriteString(h, "SignalTpFixedOverrideMainLots=" + (SignalTpFixedOverrideMainLots ? "1" : "0") + "\n");
   FileWriteString(h, "SignalTpAllocMode=" + IntegerToString((int)SignalTpAllocMode) + "\n");
   FileWriteString(h, "TGMoveSLBreakevenTP1=" + (TGMoveSLBreakevenTP1 ? "1" : "0") + "\n");
   FileWriteString(h, "TGMoveSLToTP1OnTP2=" + (TGMoveSLToTP1OnTP2 ? "1" : "0") + "\n");
   FileWriteString(h, "TrailMoveToBreakeven=" + (TrailMoveToBreakeven ? "1" : "0") + "\n");
   FileWriteString(h, "PropFirmMode=" + (PropFirmMode ? "1" : "0") + "\n");
   FileWriteString(h, "EnableDiagLog=" + (EnableDiagLog ? "1" : "0") + "\n");
   FileWriteString(h, "EnablePopupAlerts=" + (EnablePopupAlerts ? "1" : "0") + "\n");
   FileWriteString(h, "EnableSoundAlerts=" + (EnableSoundAlerts ? "1" : "0") + "\n");
   FileWriteString(h, "EnablePushNotify=" + (EnablePushNotify ? "1" : "0") + "\n");
   FileWriteString(h, "DailyLossUsePeakEquity=" + (DailyLossUsePeakEquity ? "1" : "0") + "\n");
   FileWriteString(h, "SkipIfLotOverMax=" + (SkipIfLotOverMax ? "1" : "0") + "\n");
   FileWriteString(h, "EnableMartingale=" + (EnableMartingale ? "1" : "0") + "\n");
   FileWriteString(h, "MartingaleResetOnWin=" + (MartingaleResetOnWin ? "1" : "0") + "\n");
   FileWriteString(h, "SignalCooldownSeconds=" + IntegerToString(SignalCooldownSeconds) + "\n");
   FileWriteString(h, "MaxTradesPerMinute=" + IntegerToString(MaxTradesPerMinute) + "\n");
   FileWriteString(h, "MaxLotSize=" + DoubleToString(MaxLotSize, 4) + "\n");
   FileWriteString(h, "FixedLotSize=" + DoubleToString(FixedLotSize, 4) + "\n");
   FileWriteString(h, "RiskPercent=" + DoubleToString(RiskPercent, 4) + "\n");
   FileWriteString(h, "MaxOpenPositions=" + IntegerToString(MaxOpenPositions) + "\n");
   FileWriteString(h, "LotMode=" + IntegerToString((int)LotMode) + "\n");
   FileWriteString(h, "LotMultiplier=" + DoubleToString(LotMultiplier, 4) + "\n");
   FileWriteString(h, "MaxDailyLossPercent=" + DoubleToString(MaxDailyLossPercent, 4) + "\n");
   FileWriteString(h, "MaxDailyLossAmount=" + DoubleToString(MaxDailyLossAmount, 4) + "\n");
   FileWriteString(h, "DailyResetTimezone=" + IntegerToString((int)DailyResetTimezone) + "\n");
   FileWriteString(h, "MaxSpreadPoints=" + IntegerToString(MaxSpreadPoints) + "\n");
   FileWriteString(h, "BridgePollMs=" + IntegerToString(BridgePollMs) + "\n");
   FileWriteString(h, "TelegramPollSeconds=" + IntegerToString(TelegramPollSeconds) + "\n");
   FileWriteString(h, "BridgePort=" + IntegerToString(BridgePort) + "\n");
   FileWriteString(h, "DiscordPollSeconds=" + IntegerToString(DiscordPollSeconds) + "\n");
   FileWriteString(h, "CopierPollMs=" + IntegerToString(CopierPollMs) + "\n");
   FileWriteString(h, "CopierStartupCopyMode=" + IntegerToString((int)CopierStartupCopyMode) + "\n");
   FileWriteString(h, "CopierLotMode=" + IntegerToString((int)CopierLotMode) + "\n");
   FileWriteString(h, "CopierFixedLot=" + DoubleToString(CopierFixedLot, 4) + "\n");
   FileWriteString(h, "CopierLotMultiplier=" + DoubleToString(CopierLotMultiplier, 4) + "\n");
   FileWriteString(h, "CopierRiskPercent=" + DoubleToString(CopierRiskPercent, 4) + "\n");
   FileWriteString(h, "CopierMaxLot=" + DoubleToString(CopierMaxLot, 4) + "\n");
   FileWriteString(h, "CopierMinimumLotToCopy=" + DoubleToString(CopierMinimumLotToCopy, 4) + "\n");
   FileWriteString(h, "CopierTradeCommentMode=" + IntegerToString((int)CopierTradeCommentMode) + "\n");
   FileWriteString(h, "CopierCustomTradeComment=" + CopierCustomTradeComment + "\n");
   FileWriteString(h, "DefaultSLPoints=" + IntegerToString(DefaultSLPoints) + "\n");
   FileWriteString(h, "SlippagePoints=" + IntegerToString(SlippagePoints) + "\n");
   FileWriteString(h, "EntrySlippagePips=" + DoubleToString(EntrySlippagePips, 4) + "\n");
   FileWriteString(h, "SlippageAction=" + IntegerToString((int)SlippageAction) + "\n");
   FileWriteString(h, "OppositeAction=" + IntegerToString((int)OppositeAction) + "\n");
   FileWriteString(h, "PendingExpiryHours=" + IntegerToString(PendingExpiryHours) + "\n");
   FileWriteString(h, "MinPipsDistanceSameType=" + DoubleToString(MinPipsDistanceSameType, 4) + "\n");
   FileWriteString(h, "FallbackSLPips=" + IntegerToString(FallbackSLPips) + "\n");
   FileWriteString(h, "FallbackTPPips=" + IntegerToString(FallbackTPPips) + "\n");
   FileWriteString(h, "TrailStartPips=" + IntegerToString(TrailStartPips) + "\n");
   FileWriteString(h, "TrailDistancePips=" + IntegerToString(TrailDistancePips) + "\n");
   FileWriteString(h, "TrailStepPips=" + IntegerToString(TrailStepPips) + "\n");
   FileWriteString(h, "BreakevenBufferPips=" + IntegerToString(BreakevenBufferPips) + "\n");
   FileWriteString(h, "PartialCloseMode=" + IntegerToString((int)PartialCloseMode) + "\n");
   FileWriteString(h, "PartialScope=" + IntegerToString((int)PartialScope) + "\n");
   FileWriteString(h, "PartialTP1Pips=" + DoubleToString(PartialTP1Pips, 2) + "\n");
   FileWriteString(h, "PartialTP1Lots=" + DoubleToString(PartialTP1Lots, 4) + "\n");
   FileWriteString(h, "PartialTP1Percent=" + DoubleToString(PartialTP1Percent, 2) + "\n");
   FileWriteString(h, "PartialTP2Pips=" + DoubleToString(PartialTP2Pips, 2) + "\n");
   FileWriteString(h, "PartialTP2Lots=" + DoubleToString(PartialTP2Lots, 4) + "\n");
   FileWriteString(h, "PartialTP2Percent=" + DoubleToString(PartialTP2Percent, 2) + "\n");
   FileWriteString(h, "PartialTP3Pips=" + DoubleToString(PartialTP3Pips, 2) + "\n");
   FileWriteString(h, "PartialTP3Lots=" + DoubleToString(PartialTP3Lots, 4) + "\n");
   FileWriteString(h, "PartialTP3Percent=" + DoubleToString(PartialTP3Percent, 2) + "\n");
   FileWriteString(h, "PartialTP4Pips=" + DoubleToString(PartialTP4Pips, 2) + "\n");
   FileWriteString(h, "PartialTP4Lots=" + DoubleToString(PartialTP4Lots, 4) + "\n");
   FileWriteString(h, "PartialTP4Percent=" + DoubleToString(PartialTP4Percent, 2) + "\n");
   FileWriteString(h, "PartialBEExtraPips=" + IntegerToString(PartialBEExtraPips) + "\n");
   FileWriteString(h, "TGBreakevenExtraPips=" + IntegerToString(TGBreakevenExtraPips) + "\n");
   FileWriteString(h, "MaxTPTargets=" + IntegerToString(MaxTPTargets) + "\n");
   FileWriteString(h, "NewsPauseBeforeMinutes=" + IntegerToString(NewsPauseBeforeMinutes) + "\n");
   FileWriteString(h, "NewsPauseAfterMinutes=" + IntegerToString(NewsPauseAfterMinutes) + "\n");
   FileWriteString(h, "ReportPurgeDays=" + IntegerToString(ReportPurgeDays) + "\n");
   FileWriteString(h, "MartingaleMode=" + IntegerToString((int)MartingaleMode) + "\n");
   FileWriteString(h, "MartingaleMultiplier=" + DoubleToString(MartingaleMultiplier, 4) + "\n");
   FileWriteString(h, "MartingaleFixedStep=" + DoubleToString(MartingaleFixedStep, 4) + "\n");
   FileWriteString(h, "MartingaleBaseLot=" + DoubleToString(MartingaleBaseLot, 4) + "\n");
   FileWriteString(h, "MartingaleMaxSteps=" + IntegerToString(MartingaleMaxSteps) + "\n");
   FileWriteString(h, "MartingaleMaxLoss=" + DoubleToString(MartingaleMaxLoss, 4) + "\n");
   FileWriteString(h, "TelegramBotToken=" + TelegramBotToken + "\n");
   FileWriteString(h, "TelegramChatID=" + TelegramChatID + "\n");
   FileWriteString(h, "AllowedBridgeSources=" + AllowedBridgeSources + "\n");
   FileWriteString(h, "DiscordWebhookURL=" + DiscordWebhookURL + "\n");
   FileWriteString(h, "SymbolSuffix=" + SymbolSuffix + "\n");
   FileWriteString(h, "CustomMappings=" + CustomMappings + "\n");
   FileWriteString(h, "TelegramSendTag=" + TelegramSendTag + "\n");
   FileWriteString(h, "TelegramSendSuffix=" + TelegramSendSuffix + "\n");
   FileWriteString(h, "SendBotToken=" + SendBotToken + "\n");
   FileWriteString(h, "SendChatID=" + SendChatID + "\n");
   FileWriteString(h, "CopierFileName=" + CopierFileName + "\n");
   FileWriteString(h, "CustomSLKeywords=" + CustomSLKeywords + "\n");
   FileWriteString(h, "CustomTPKeywords=" + CustomTPKeywords + "\n");
   FileWriteString(h, "MoveSLCommands=" + MoveSLCommands + "\n");
   FileWriteString(h, "CloseAllCommands=" + CloseAllCommands + "\n");
   FileWriteString(h, "SkipKeywords=" + SkipKeywords + "\n");
   FileWriteString(h, "KeywordReplaceMap=" + KeywordReplaceMap + "\n");
   FileWriteString(h, "LotDistribution=" + LotDistribution + "\n");
   FileWriteString(h, "SignalTpLotValues=" + SignalTpLotValues + "\n");
   FileWriteString(h, "WhitelistSymbols=" + WhitelistSymbols + "\n");
   FileWriteString(h, "BlacklistSymbols=" + BlacklistSymbols + "\n");
   FileWriteString(h, "NewsPauseCurrencies=" + NewsPauseCurrencies + "\n");
   FileWriteString(h, "DiagLogFileName=" + DiagLogFileName + "\n");
   FileWriteString(h, "AlertSoundFile=" + AlertSoundFile + "\n");
   FileWriteString(h, "PerSymbolLots=" + PerSymbolLots + "\n");
   FileWriteString(h, "MGPerSymbolLots=" + MGPerSymbolLots + "\n");
   FileClose(h);
   g_tcuProfileStatus = "Saved: " + fn; g_tcuProfileStatusAt = GetTickCount64();
   Print("[TCU] Profile exported: ", fn);
}

void TCU_ImportProfile(string name)
{
   StringTrimLeft(name); StringTrimRight(name);
   if(StringLen(name) == 0) name = "MyProfile";
   StringReplace(name, "/", "_"); StringReplace(name, "\\", "_"); StringReplace(name, ":", "_");
   string fn = "TCU_Profile_" + name + ".cfg";
   if(!FileIsExist(fn, FILE_COMMON)) { g_tcuProfileStatus = "NOT FOUND: " + fn; g_tcuProfileStatusAt = GetTickCount64(); return; }
   int h = FileOpen(fn, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) { g_tcuProfileStatus = "ERROR: cannot read " + fn; g_tcuProfileStatusAt = GetTickCount64(); return; }
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(StringLen(line) == 0 || StringGetCharacter(line, 0) == '#') continue;
      int sep = StringFind(line, "="); if(sep < 1) continue;
      string key = StringSubstr(line, 0, sep);
      string val = StringSubstr(line, sep + 1);
      if(key=="ArmExecution")             ArmExecution             = val=="1";
      else if(key=="DisarmOnRestart")          DisarmOnRestart          = val=="1";
      else if(key=="EnableBridgeMode")         EnableBridgeMode         = val=="1";
      else if(key=="EnableBotAPIMode")         EnableBotAPIMode         = val=="1";
      else if(key=="EnableDiscordMode")        EnableDiscordMode        = val=="1";
      else if(key=="CopierMode")               CopierMode               = (ENUM_COPIER_MODE)(int)StringToInteger(val);
      else if(key=="CopierAutoClose")          CopierAutoClose          = val=="1";
      else if(key=="EnableReportLog")          EnableReportLog          = val=="1";
      else if(key=="EnableTelegramSend")       EnableTelegramSend       = val=="1";
      else if(key=="UseSeparateSendBot")       UseSeparateSendBot       = val=="1";
      else if(key=="CopySL")                   CopySL                   = val=="1";
      else if(key=="CopyTP")                   CopyTP                   = val=="1";
      else if(key=="ReverseSignal")            ReverseSignal            = val=="1";
      else if(key=="EnableMultiTP")            EnableMultiTP            = val=="1";
      else if(key=="EnablePendingOrders")      EnablePendingOrders      = val=="1";
      else if(key=="EnablePendingExpiry")      EnablePendingExpiry      = val=="1";
      else if(key=="EnablePendingMultiTP")     EnablePendingMultiTP     = val=="1";
      else if(key=="EnableDuplicateFilter")    EnableDuplicateFilter    = val=="1";
      else if(key=="DuplicateWindowMinutes")   DuplicateWindowMinutes   = MathMax(1,(int)StringToInteger(val));
      else if(key=="EnableTrailingStop")       EnableTrailingStop       = val=="1";
      else if(key=="EnablePartialClose")       EnablePartialClose       = val=="1";
      else if(key=="EnableAutoSL")             EnableAutoSL             = val=="1";
      else if(key=="EnableAutoTP")             EnableAutoTP             = val=="1";
      else if(key=="EnableNewsPause")          EnableNewsPause          = val=="1";
      else if(key=="NewsPauseHighImpact")      NewsPauseHighImpact      = val=="1";
      else if(key=="NewsPauseMediumImpact")    NewsPauseMediumImpact    = val=="1";
      else if(key=="EnableWhitelist")          EnableWhitelist          = val=="1";
      else if(key=="EnableBlacklist")          EnableBlacklist          = val=="1";
      else if(key=="EnableSkipKeywords")       EnableSkipKeywords       = val=="1";
      else if(key=="EnableTimeFilter")         EnableTimeFilter         = val=="1";
      else if(key=="EnableSpreadFilter")       EnableSpreadFilter       = val=="1";
      else if(key=="EnableSlippageFilter")     EnableSlippageFilter     = val=="1";
      else if(key=="RequireEntryArmour")       RequireEntryArmour       = val=="1";
      else if(key=="ModifySLTPIfPositionExists") ModifySLTPIfPositionExists = val=="1";
      else if(key=="SkipSignalWithoutSL")      SkipSignalWithoutSL      = val=="1";
      else if(key=="SkipSignalWithoutTP")      SkipSignalWithoutTP      = val=="1";
      else if(key=="EnableSignalTP")           EnableSignalTP           = val=="1";
      else if(key=="AllowSLTPModDuringCooldown") AllowSLTPModDuringCooldown = val=="1";
      else if(key=="EnableCommandReplies")     EnableCommandReplies     = val=="1";
      else if(key=="EnableKeywordReplace")     EnableKeywordReplace     = val=="1";
      else if(key=="EnableCustomSLTPKeywords") EnableCustomSLTPKeywords = val=="1";
      else if(key=="EnablePartialAlerts")      EnablePartialAlerts      = val=="1";
      else if(key=="PartialMoveSLBreakeven")   PartialMoveSLBreakeven   = val=="1";
      else if(key=="PartialMoveSLToTP1")       PartialMoveSLToTP1       = val=="1";
      else if(key=="PartialMoveSLToTP2")       PartialMoveSLToTP2       = val=="1";
      else if(key=="PartialMoveSLToTP3")       PartialMoveSLToTP3       = val=="1";
      else if(key=="SignalTpFixedOverrideMainLots") SignalTpFixedOverrideMainLots = val=="1";
      else if(key=="SignalTpAllocMode")        SignalTpAllocMode        = (ENUM_PARTIAL_MODE)(int)StringToInteger(val);
      else if(key=="TGMoveSLBreakevenTP1")     TGMoveSLBreakevenTP1     = val=="1";
      else if(key=="TGMoveSLToTP1OnTP2")       TGMoveSLToTP1OnTP2       = val=="1";
      else if(key=="TrailMoveToBreakeven")     TrailMoveToBreakeven     = val=="1";
      else if(key=="PropFirmMode")             PropFirmMode             = val=="1";
      else if(key=="EnableDiagLog")            EnableDiagLog            = val=="1";
      else if(key=="EnablePopupAlerts")        EnablePopupAlerts        = val=="1";
      else if(key=="EnableSoundAlerts")        EnableSoundAlerts        = val=="1";
      else if(key=="EnablePushNotify")         EnablePushNotify         = val=="1";
      else if(key=="DailyLossUsePeakEquity")   DailyLossUsePeakEquity   = val=="1";
      else if(key=="SkipIfLotOverMax")         SkipIfLotOverMax         = val=="1";
      else if(key=="EnableMartingale")         EnableMartingale         = val=="1";
      else if(key=="MartingaleResetOnWin")     MartingaleResetOnWin     = val=="1";
      else if(key=="SignalCooldownSeconds")    SignalCooldownSeconds     = MathMax(0,(int)StringToInteger(val));
      else if(key=="MaxTradesPerMinute")       MaxTradesPerMinute       = MathMax(0,(int)StringToInteger(val));
      else if(key=="MaxLotSize")               MaxLotSize               = StringToDouble(val);
      else if(key=="FixedLotSize")             FixedLotSize             = StringToDouble(val);
      else if(key=="RiskPercent")              RiskPercent              = StringToDouble(val);
      else if(key=="MaxOpenPositions")         MaxOpenPositions         = MathMax(0,(int)StringToInteger(val));
      else if(key=="LotMode")                  LotMode                  = (ENUM_LOT_MODE)(int)StringToInteger(val);
      else if(key=="LotMultiplier")            LotMultiplier            = StringToDouble(val);
      else if(key=="MaxDailyLossPercent")      MaxDailyLossPercent      = StringToDouble(val);
      else if(key=="MaxDailyLossAmount")       MaxDailyLossAmount       = StringToDouble(val);
      else if(key=="DailyResetTimezone")       DailyResetTimezone       = (ENUM_DAILY_RESET_TZ)(int)StringToInteger(val);
      else if(key=="MaxSpreadPoints")          MaxSpreadPoints          = MathMax(0,(int)StringToInteger(val));
      else if(key=="BridgePollMs")             BridgePollMs             = MathMax(200,(int)StringToInteger(val));
      else if(key=="TelegramPollSeconds")      TelegramPollSeconds      = MathMax(1,(int)StringToInteger(val));
      else if(key=="BridgePort")               BridgePort               = MathMax(1,(int)StringToInteger(val));
      else if(key=="DiscordPollSeconds")       DiscordPollSeconds       = MathMax(1,(int)StringToInteger(val));
      else if(key=="CopierPollMs")             CopierPollMs             = MathMax(20,(int)StringToInteger(val));
      else if(key=="CopierStartupCopyMode")    CopierStartupCopyMode    = (ENUM_STARTUP_COPY_MODE)(int)StringToInteger(val);
      else if(key=="CopierLotMode")            CopierLotMode            = (ENUM_COPIER_LOT_MODE)(int)StringToInteger(val);
      else if(key=="CopierFixedLot")           CopierFixedLot           = StringToDouble(val);
      else if(key=="CopierLotMultiplier")      CopierLotMultiplier      = StringToDouble(val);
      else if(key=="CopierRiskPercent")        CopierRiskPercent        = StringToDouble(val);
      else if(key=="CopierMaxLot")             CopierMaxLot             = StringToDouble(val);
      else if(key=="CopierMinimumLotToCopy")   CopierMinimumLotToCopy   = MathMax(0.0, StringToDouble(val));
      else if(key=="CopierTradeCommentMode")   CopierTradeCommentMode   = (ENUM_TRADE_COMMENT_MODE)(int)StringToInteger(val);
      else if(key=="DefaultSLPoints")          DefaultSLPoints          = MathMax(0,(int)StringToInteger(val));
      else if(key=="SlippagePoints")           SlippagePoints           = MathMax(0,(int)StringToInteger(val));
      else if(key=="EntrySlippagePips")        EntrySlippagePips        = StringToDouble(val);
      else if(key=="SlippageAction")           SlippageAction           = (ENUM_SLIPPAGE_ACTION)(int)StringToInteger(val);
      else if(key=="OppositeAction")           OppositeAction           = (ENUM_OPPOSITE_ACTION)(int)StringToInteger(val);
      else if(key=="PendingExpiryHours")       PendingExpiryHours       = MathMax(1,(int)StringToInteger(val));
      else if(key=="MinPipsDistanceSameType")  MinPipsDistanceSameType  = StringToDouble(val);
      else if(key=="FallbackSLPips")           FallbackSLPips           = MathMax(0,(int)StringToInteger(val));
      else if(key=="FallbackTPPips")           FallbackTPPips           = MathMax(0,(int)StringToInteger(val));
      else if(key=="TrailStartPips")           TrailStartPips           = MathMax(1,(int)StringToInteger(val));
      else if(key=="TrailDistancePips")        TrailDistancePips        = MathMax(1,(int)StringToInteger(val));
      else if(key=="TrailStepPips")            TrailStepPips            = MathMax(1,(int)StringToInteger(val));
      else if(key=="BreakevenBufferPips")      BreakevenBufferPips      = MathMax(0,(int)StringToInteger(val));
      else if(key=="PartialCloseMode")         PartialCloseMode         = (ENUM_PARTIAL_MODE)(int)StringToInteger(val);
      else if(key=="PartialScope")             PartialScope             = (ENUM_PARTIAL_SCOPE)(int)StringToInteger(val);
      else if(key=="PartialTP1Pips")           PartialTP1Pips           = StringToDouble(val);
      else if(key=="PartialTP1Lots")           PartialTP1Lots           = StringToDouble(val);
      else if(key=="PartialTP1Percent")        PartialTP1Percent        = StringToDouble(val);
      else if(key=="PartialTP2Pips")           PartialTP2Pips           = StringToDouble(val);
      else if(key=="PartialTP2Lots")           PartialTP2Lots           = StringToDouble(val);
      else if(key=="PartialTP2Percent")        PartialTP2Percent        = StringToDouble(val);
      else if(key=="PartialTP3Pips")           PartialTP3Pips           = StringToDouble(val);
      else if(key=="PartialTP3Lots")           PartialTP3Lots           = StringToDouble(val);
      else if(key=="PartialTP3Percent")        PartialTP3Percent        = StringToDouble(val);
      else if(key=="PartialTP4Pips")           PartialTP4Pips           = StringToDouble(val);
      else if(key=="PartialTP4Lots")           PartialTP4Lots           = StringToDouble(val);
      else if(key=="PartialTP4Percent")        PartialTP4Percent        = StringToDouble(val);
      else if(key=="PartialBEExtraPips")       PartialBEExtraPips       = MathMax(0,(int)StringToInteger(val));
      else if(key=="TGBreakevenExtraPips")     TGBreakevenExtraPips     = MathMax(0,(int)StringToInteger(val));
      else if(key=="MaxTPTargets")             MaxTPTargets             = (int)TCU_ClampDouble((double)StringToInteger(val),1,3);
      else if(key=="NewsPauseBeforeMinutes")   NewsPauseBeforeMinutes   = MathMax(0,(int)StringToInteger(val));
      else if(key=="NewsPauseAfterMinutes")    NewsPauseAfterMinutes    = MathMax(0,(int)StringToInteger(val));
      else if(key=="ReportPurgeDays")          ReportPurgeDays          = MathMax(1,(int)StringToInteger(val));
      else if(key=="MartingaleMode")           MartingaleMode           = (int)StringToInteger(val);
      else if(key=="MartingaleMultiplier")     MartingaleMultiplier     = StringToDouble(val);
      else if(key=="MartingaleFixedStep")      MartingaleFixedStep      = StringToDouble(val);
      else if(key=="MartingaleBaseLot")        MartingaleBaseLot        = StringToDouble(val);
      else if(key=="MartingaleMaxSteps")       MartingaleMaxSteps       = MathMax(1,(int)StringToInteger(val));
   else if(key=="MartingaleMaxLoss")       MartingaleMaxLoss        = StringToDouble(val);
      else if(key=="TelegramBotToken")         TelegramBotToken         = val;
      else if(key=="TelegramChatID")           TelegramChatID           = val;
      else if(key=="AllowedBridgeSources")     AllowedBridgeSources     = val;
      else if(key=="DiscordWebhookURL")        DiscordWebhookURL        = val;
      else if(key=="SymbolSuffix")             SymbolSuffix             = val;
      else if(key=="CustomMappings")           CustomMappings           = val;
      else if(key=="TelegramSendTag")          TelegramSendTag          = val;
      else if(key=="TelegramSendSuffix")       TelegramSendSuffix       = val;
      else if(key=="SendBotToken")             SendBotToken             = val;
      else if(key=="SendChatID")               SendChatID               = val;
      else if(key=="CopierFileName")           CopierFileName           = val;
      else if(key=="CopierCustomTradeComment") CopierCustomTradeComment = val;
      else if(key=="CustomSLKeywords")         CustomSLKeywords         = val;
      else if(key=="CustomTPKeywords")         CustomTPKeywords         = val;
      else if(key=="MoveSLCommands")           MoveSLCommands           = val;
      else if(key=="CloseAllCommands")         CloseAllCommands         = val;
      else if(key=="SkipKeywords")             SkipKeywords             = val;
      else if(key=="KeywordReplaceMap")        KeywordReplaceMap        = val;
      else if(key=="LotDistribution")          LotDistribution          = val;
      else if(key=="SignalTpLotValues")        SignalTpLotValues        = val;
      else if(key=="WhitelistSymbols")         WhitelistSymbols         = val;
      else if(key=="BlacklistSymbols")         BlacklistSymbols         = val;
      else if(key=="NewsPauseCurrencies")      NewsPauseCurrencies      = val;
      else if(key=="DiagLogFileName")          DiagLogFileName          = val;
      else if(key=="AlertSoundFile")           AlertSoundFile           = val;
      else if(key=="PerSymbolLots")            PerSymbolLots            = val;
      else if(key=="MGPerSymbolLots")          MGPerSymbolLots          = val;
   }
   FileClose(h);
   TCU_CommitSettings();
   g_tcuProfileStatus = "Loaded: " + fn; g_tcuProfileStatusAt = GetTickCount64();
   Print("[TCU] Profile imported: ", fn);
}

void SaveStringSettings()
{
   string fn = _CfgFile();
   int h = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) { Print("[TCU] Cannot save string settings: ", fn); return; }
   FileWriteString(h, "InputSignature="     + TCU_CurrentInputSignature() + "\n");
   FileWriteString(h, "TelegramBotToken="    + TelegramBotToken    + "\n");
   FileWriteString(h, "TelegramChatID="      + TelegramChatID      + "\n");
   FileWriteString(h, "AllowedBridgeSources=" + AllowedBridgeSources + "\n");
   FileWriteString(h, "DiscordWebhookURL="   + DiscordWebhookURL   + "\n");
   FileWriteString(h, "SymbolSuffix="        + SymbolSuffix        + "\n");
   FileWriteString(h, "CustomMappings="      + CustomMappings      + "\n");
   FileWriteString(h, "TelegramSendTag="     + TelegramSendTag     + "\n");
   FileWriteString(h, "TelegramSendSuffix="  + TelegramSendSuffix  + "\n");
   FileWriteString(h, "SendBotToken="        + SendBotToken        + "\n");
   FileWriteString(h, "SendChatID="          + SendChatID          + "\n");
   FileWriteString(h, "CopierFileName="      + CopierFileName      + "\n");
   FileWriteString(h, "CopierCustomTradeComment=" + CopierCustomTradeComment + "\n");
   FileWriteString(h, "CustomSLKeywords="    + CustomSLKeywords    + "\n");
   FileWriteString(h, "CustomTPKeywords="    + CustomTPKeywords    + "\n");
   FileWriteString(h, "MoveSLCommands="      + MoveSLCommands      + "\n");
   FileWriteString(h, "CloseAllCommands="    + CloseAllCommands    + "\n");
   FileWriteString(h, "SkipKeywords="        + SkipKeywords        + "\n");
   FileWriteString(h, "KeywordReplaceMap="   + KeywordReplaceMap   + "\n");
   FileWriteString(h, "LotDistribution="     + LotDistribution     + "\n");
   FileWriteString(h, "SignalTpLotValues="   + SignalTpLotValues   + "\n");
   FileWriteString(h, "WhitelistSymbols="    + WhitelistSymbols    + "\n");
   FileWriteString(h, "BlacklistSymbols="    + BlacklistSymbols    + "\n");
   FileWriteString(h, "NewsPauseCurrencies=" + NewsPauseCurrencies + "\n");
   FileWriteString(h, "DiagLogFileName="     + DiagLogFileName     + "\n");
   FileWriteString(h, "AlertSoundFile="      + AlertSoundFile      + "\n");
   FileWriteString(h, "PerSymbolLots="       + PerSymbolLots       + "\n");  // [v6.00 NEW][PerSymbolLots]
   FileWriteString(h, "MGPerSymbolLots="    + MGPerSymbolLots    + "\n");  // [v6.00 NEW][MGPerSymbolLots]
   FileClose(h);
   g_tcuLastSavedStringState = TCU_CurrentStringSettingsState();
}

bool LoadStringSettings()
{
   string fn = _CfgFile();
   if(!FileIsExist(fn, FILE_COMMON)) return false;
   int h = FileOpen(fn, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return false;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(StringLen(line) == 0) continue;
      int sep = StringFind(line, "=");
      if(sep < 1) continue;
      string key = StringSubstr(line, 0, sep);
      string val = StringSubstr(line, sep + 1);
      if(key == "TelegramBotToken")   TelegramBotToken   = val;
      else if(key == "TelegramChatID")     TelegramChatID     = val;
      else if(key == "AllowedBridgeSources") AllowedBridgeSources = val;
      else if(key == "DiscordWebhookURL")  DiscordWebhookURL  = val;
      else if(key == "SymbolSuffix")       SymbolSuffix       = val;
      else if(key == "CustomMappings")     CustomMappings     = val;
      else if(key == "TelegramSendTag")    TelegramSendTag    = val;
      else if(key == "TelegramSendSuffix") TelegramSendSuffix = val;
      else if(key == "SendBotToken")       SendBotToken       = val;
      else if(key == "SendChatID")         SendChatID         = val;
      else if(key == "CopierFileName")     CopierFileName     = val;
      else if(key == "CopierCustomTradeComment") CopierCustomTradeComment = val;
      else if(key == "CustomSLKeywords")   CustomSLKeywords   = val;
      else if(key == "CustomTPKeywords")   CustomTPKeywords   = val;
      else if(key == "MoveSLCommands")     MoveSLCommands     = val;
      else if(key == "CloseAllCommands")   CloseAllCommands   = val;
      else if(key == "SkipKeywords")       SkipKeywords       = val;
      else if(key == "KeywordReplaceMap")  KeywordReplaceMap  = val;
      else if(key == "LotDistribution")    LotDistribution    = val;
      else if(key == "SignalTpLotValues")  SignalTpLotValues  = val;
      else if(key == "WhitelistSymbols")   WhitelistSymbols   = val;
      else if(key == "BlacklistSymbols")   BlacklistSymbols   = val;
      else if(key == "NewsPauseCurrencies") NewsPauseCurrencies = val;
      else if(key == "DiagLogFileName")    DiagLogFileName    = val;
      else if(key == "AlertSoundFile")     AlertSoundFile     = val;
      else if(key == "PerSymbolLots")      PerSymbolLots      = val;  // [v6.00 NEW][PerSymbolLots]
      else if(key == "MGPerSymbolLots")    MGPerSymbolLots    = val;  // [v6.00 NEW][MGPerSymbolLots]
   }
   FileClose(h);
   g_tcuLastSavedStringState = TCU_CurrentStringSettingsState();
   Print("[TCU] String settings loaded from ", fn);
   return true;
}

void SaveSettings()
{
   string p = "TCU_" + IntegerToString(MagicNumber) + "_";
   // Keep the legacy ArmExecution key for saved-profile detection, but the
   // effective startup arm state is decided separately during OnInit.
   GlobalVariableSet(p+"ArmExecution",          0);
   GlobalVariableSet(p+"SavedArmState",         ArmExecution          ? 1 : 0);
   GlobalVariableSet(p+"DisarmOnRestart",       DisarmOnRestart       ? 1 : 0);
   GlobalVariableSet(p+"EnableBridgeMode",       EnableBridgeMode      ? 1 : 0);
   GlobalVariableSet(p+"EnableBotAPIMode",       EnableBotAPIMode      ? 1 : 0);
   GlobalVariableSet(p+"EnableDiscordMode",      EnableDiscordMode     ? 1 : 0);
   // CopierMode is an enum, save as double
   GlobalVariableSet(p+"CopierMode",             (double)CopierMode);
   GlobalVariableSet(p+"CopierAutoClose",        CopierAutoClose       ? 1 : 0);
   GlobalVariableSet(p+"EnableReportLog",        EnableReportLog       ? 1 : 0);
   GlobalVariableSet(p+"EnableTelegramSend",     EnableTelegramSend    ? 1 : 0);
   GlobalVariableSet(p+"UseSeparateSendBot",     UseSeparateSendBot    ? 1 : 0);
   GlobalVariableSet(p+"CopySL",                 CopySL                ? 1 : 0);
   GlobalVariableSet(p+"CopyTP",                 CopyTP                ? 1 : 0);
   GlobalVariableSet(p+"ReverseSignal",          ReverseSignal         ? 1 : 0);
   GlobalVariableSet(p+"EnableMultiTP",          EnableMultiTP         ? 1 : 0);
   GlobalVariableSet(p+"EnablePendingOrders",    EnablePendingOrders   ? 1 : 0);
   GlobalVariableSet(p+"EnablePendingExpiry",    EnablePendingExpiry   ? 1 : 0);
   GlobalVariableSet(p+"EnablePendingMultiTP",   EnablePendingMultiTP  ? 1 : 0);
   GlobalVariableSet(p+"EnableDuplicateFilter",  EnableDuplicateFilter ? 1 : 0);
   GlobalVariableSet(p+"DuplicateWindowMin",     DuplicateWindowMinutes);
   GlobalVariableSet(p+"EnableTrailingStop",     EnableTrailingStop    ? 1 : 0);
   GlobalVariableSet(p+"EnablePartialClose",     EnablePartialClose    ? 1 : 0);
   GlobalVariableSet(p+"EnableAutoSL",           EnableAutoSL          ? 1 : 0);
   GlobalVariableSet(p+"EnableAutoTP",           EnableAutoTP          ? 1 : 0);
   GlobalVariableSet(p+"EnableNewsPause",        EnableNewsPause       ? 1 : 0);
   GlobalVariableSet(p+"NewsPauseHighImpact",    NewsPauseHighImpact   ? 1 : 0);
   GlobalVariableSet(p+"NewsPauseMediumImpact",  NewsPauseMediumImpact ? 1 : 0);
   GlobalVariableSet(p+"EnableWhitelist",        EnableWhitelist       ? 1 : 0);
   GlobalVariableSet(p+"EnableBlacklist",        EnableBlacklist       ? 1 : 0);
   GlobalVariableSet(p+"EnableSkipKeywords",     EnableSkipKeywords    ? 1 : 0);
   GlobalVariableSet(p+"EnableTimeFilter",       EnableTimeFilter      ? 1 : 0);
   GlobalVariableSet(p+"EnableSpreadFilter",     EnableSpreadFilter    ? 1 : 0);
   GlobalVariableSet(p+"EnableSlippageFilter",   EnableSlippageFilter  ? 1 : 0);
   GlobalVariableSet(p+"RequireEntryArmour",     RequireEntryArmour    ? 1 : 0);
   GlobalVariableSet(p+"ModifySLTPIfPositionExists", ModifySLTPIfPositionExists ? 1 : 0);
   GlobalVariableSet(p+"SkipSignalWithoutSL",    SkipSignalWithoutSL   ? 1 : 0);
   GlobalVariableSet(p+"SkipSignalWithoutTP",    SkipSignalWithoutTP   ? 1 : 0);
   GlobalVariableSet(p+"EnableSignalTP",         EnableSignalTP        ? 1 : 0);
   GlobalVariableSet(p+"AllowSLTPModDuringCooldown", AllowSLTPModDuringCooldown ? 1 : 0);
   GlobalVariableSet(p+"EnableCommandReplies",   EnableCommandReplies  ? 1 : 0);
   GlobalVariableSet(p+"EnableKeywordReplace",   EnableKeywordReplace  ? 1 : 0);
   GlobalVariableSet(p+"EnableCustomSLTPKeywords", EnableCustomSLTPKeywords ? 1 : 0);
   GlobalVariableSet(p+"EnablePartialAlerts",    EnablePartialAlerts   ? 1 : 0);
   GlobalVariableSet(p+"PartialMoveSLBreakeven", PartialMoveSLBreakeven ? 1 : 0);
   GlobalVariableSet(p+"PartialMoveSLToTP1",     PartialMoveSLToTP1    ? 1 : 0);
   GlobalVariableSet(p+"PartialMoveSLToTP2",     PartialMoveSLToTP2    ? 1 : 0);
   GlobalVariableSet(p+"PartialMoveSLToTP3",     PartialMoveSLToTP3    ? 1 : 0);
   GlobalVariableSet(p+"SignalTpFixedOverrideMainLots", SignalTpFixedOverrideMainLots ? 1 : 0);
   GlobalVariableSet(p+"SignalTpAllocMode",      (double)SignalTpAllocMode);
   GlobalVariableSet(p+"TGMoveSLBreakevenTP1",   TGMoveSLBreakevenTP1  ? 1 : 0);
   GlobalVariableSet(p+"TGMoveSLToTP1OnTP2",     TGMoveSLToTP1OnTP2    ? 1 : 0);
   GlobalVariableSet(p+"TrailMoveToBreakeven",   TrailMoveToBreakeven  ? 1 : 0);
   GlobalVariableSet(p+"PropFirmMode",           PropFirmMode          ? 1 : 0);
   GlobalVariableSet(p+"EnableDiagLog",          EnableDiagLog         ? 1 : 0);
   GlobalVariableSet(p+"EnablePopupAlerts",      EnablePopupAlerts     ? 1 : 0);
   GlobalVariableSet(p+"EnableSoundAlerts",      EnableSoundAlerts     ? 1 : 0);
   GlobalVariableSet(p+"EnablePushNotify",       EnablePushNotify      ? 1 : 0);
   // Numeric values
   GlobalVariableSet(p+"SignalCooldownSec",      SignalCooldownSeconds);
   GlobalVariableSet(p+"MaxTradesPerMinute",     MaxTradesPerMinute);
   GlobalVariableSet(p+"MaxLotSize",             MaxLotSize);
   GlobalVariableSet(p+"FixedLotSize",           FixedLotSize);
   GlobalVariableSet(p+"RiskPercent",            RiskPercent);
   GlobalVariableSet(p+"MaxOpenPositions",       MaxOpenPositions);
   GlobalVariableSet(p+"LotMultiplier",          LotMultiplier);
   GlobalVariableSet(p+"MaxDailyLossPercent",    MaxDailyLossPercent);
   GlobalVariableSet(p+"MaxDailyLossAmount",     MaxDailyLossAmount);
   GlobalVariableSet(p+"DailyResetTimezone",     (double)DailyResetTimezone);
   GlobalVariableSet(p+"DailyLossUsePeakEquity", DailyLossUsePeakEquity ? 1 : 0);
   GlobalVariableSet(p+"MaxSpreadPoints",        MaxSpreadPoints);
   GlobalVariableSet(p+"BridgePollMs",           BridgePollMs);
   GlobalVariableSet(p+"TelegramPollSeconds",    TelegramPollSeconds);
   GlobalVariableSet(p+"BridgePort",             BridgePort);
   GlobalVariableSet(p+"DiscordPollSeconds",     DiscordPollSeconds);
   GlobalVariableSet(p+"CopierPollMs",           CopierPollMs);
   GlobalVariableSet(p+"CopierStartupMode",      (double)CopierStartupCopyMode);
   GlobalVariableSet(p+"CopierLotMode",          (double)CopierLotMode);
   GlobalVariableSet(p+"CopierFixedLot",         CopierFixedLot);
   GlobalVariableSet(p+"CopierLotMultiplier",    CopierLotMultiplier);
   GlobalVariableSet(p+"CopierRiskPercent",      CopierRiskPercent);
   GlobalVariableSet(p+"CopierMaxLot",           CopierMaxLot);
   GlobalVariableSet(p+"CopierMinLotToCopy",     CopierMinimumLotToCopy);
   GlobalVariableSet(p+"CopierCommentMode",      (double)CopierTradeCommentMode);
   GlobalVariableSet(p+"DefaultSLPoints",        DefaultSLPoints);
   GlobalVariableSet(p+"SkipIfLotOverMax",       SkipIfLotOverMax ? 1 : 0);
   GlobalVariableSet(p+"SlippagePoints",         SlippagePoints);
   GlobalVariableSet(p+"EntrySlippagePips",      EntrySlippagePips);
   GlobalVariableSet(p+"SlippageAction",         (double)SlippageAction);
   GlobalVariableSet(p+"OppositeAction",         (double)OppositeAction);
   GlobalVariableSet(p+"PendingExpiryHours",     PendingExpiryHours);
   GlobalVariableSet(p+"MinPipsDistanceSameType", MinPipsDistanceSameType);
   GlobalVariableSet(p+"FallbackSLPips",         FallbackSLPips);
   GlobalVariableSet(p+"FallbackTPPips",         FallbackTPPips);
   GlobalVariableSet(p+"TrailStartPips",         TrailStartPips);
   GlobalVariableSet(p+"TrailDistancePips",      TrailDistancePips);
   GlobalVariableSet(p+"TrailStepPips",          TrailStepPips);
   GlobalVariableSet(p+"BreakevenBufferPips",    BreakevenBufferPips);
   GlobalVariableSet(p+"PartialCloseMode",       (double)PartialCloseMode);
   GlobalVariableSet(p+"PartialScope",           (double)PartialScope);
   GlobalVariableSet(p+"PartialTP1Pips",         PartialTP1Pips);
   GlobalVariableSet(p+"PartialTP1Lots",         PartialTP1Lots);
   GlobalVariableSet(p+"PartialTP1Percent",      PartialTP1Percent);
   GlobalVariableSet(p+"PartialTP2Pips",         PartialTP2Pips);
   GlobalVariableSet(p+"PartialTP2Lots",         PartialTP2Lots);
   GlobalVariableSet(p+"PartialTP2Percent",      PartialTP2Percent);
   GlobalVariableSet(p+"PartialTP3Pips",         PartialTP3Pips);
   GlobalVariableSet(p+"PartialTP3Lots",         PartialTP3Lots);
   GlobalVariableSet(p+"PartialTP3Percent",      PartialTP3Percent);
   GlobalVariableSet(p+"PartialTP4Pips",         PartialTP4Pips);
   GlobalVariableSet(p+"PartialTP4Lots",         PartialTP4Lots);
   GlobalVariableSet(p+"PartialTP4Percent",      PartialTP4Percent);
   GlobalVariableSet(p+"PartialBEExtraPips",     PartialBEExtraPips);
   GlobalVariableSet(p+"TGBreakevenExtraPips",   TGBreakevenExtraPips);
   GlobalVariableSet(p+"MaxTPTargets",           MaxTPTargets);
   GlobalVariableSet(p+"NewsPauseBeforeMinutes", NewsPauseBeforeMinutes);
   GlobalVariableSet(p+"NewsPauseAfterMinutes",  NewsPauseAfterMinutes);
   GlobalVariableSet(p+"ReportPurgeDays",        ReportPurgeDays);
   GlobalVariableSet(p+"PanelMode",              (double)PanelMode);
   // [MARTINGALE]
   GlobalVariableSet(p+"EnableMartingale",       EnableMartingale     ? 1 : 0);
   GlobalVariableSet(p+"MartingaleMode",         (double)MartingaleMode);
   GlobalVariableSet(p+"MartingaleMultiplier",   MartingaleMultiplier);
   GlobalVariableSet(p+"MartingaleFixedStep",    MartingaleFixedStep);
   GlobalVariableSet(p+"MartingaleBaseLot",       MartingaleBaseLot);
   GlobalVariableSet(p+"MartingaleMaxSteps",     MartingaleMaxSteps);
   GlobalVariableSet(p+"MartingaleResetOnWin",   MartingaleResetOnWin ? 1 : 0);
   GlobalVariableSet(p+"MartingaleMaxLoss",      MartingaleMaxLoss);
   GlobalVariableSet(p+"MartingaleActivationTime", (double)g_mgActivationTime);
   // [MARTINGALE STREAKS] Persist per-symbol streak state so it survives EA restart
   GlobalVariableSet(p+"MG_COUNT", (double)g_mgCount);
   for(int _mgi = 0; _mgi < g_mgCount; _mgi++)
   {
      string _mgk = p + "MG_" + IntegerToString(_mgi) + "_";
      GlobalVariableSet(_mgk + "SYM",    0); // sym stored via name trick below
      GlobalVariableSet(_mgk + "STREAK", (double)g_mgTable[_mgi].streak);
      GlobalVariableSet(_mgk + "PNL",    g_mgTable[_mgi].mgPnl);
      GlobalVariableSet(_mgk + "WINS",   (double)g_mgTable[_mgi].wins);
      GlobalVariableSet(_mgk + "LOSSES", (double)g_mgTable[_mgi].losses);
      GlobalVariableSet(_mgk + "CARRY",  g_mgTable[_mgi].carry);
      GlobalVariableSet(_mgk + "RECTGT", g_mgTable[_mgi].recTarget);
      // Store symbol name as a GlobalVariable name suffix (encode char by char)
      string _s = g_mgTable[_mgi].sym;
      GlobalVariableSet(_mgk + "SYMLEN", (double)StringLen(_s));
      for(int _sc = 0; _sc < StringLen(_s) && _sc < 32; _sc++)
         GlobalVariableSet(_mgk + "SC" + IntegerToString(_sc), (double)StringGetCharacter(_s, _sc));
   }
   string stringState = TCU_CurrentStringSettingsState();
   if(stringState != g_tcuLastSavedStringState)
      SaveStringSettings();
}

bool LoadSettings()
{
   string p = "TCU_" + IntegerToString(MagicNumber) + "_";
   // Only load if we have at least one saved setting
   if(!GlobalVariableCheck(p+"ArmExecution")) return false;
   ArmExecution          = false;
   if(GlobalVariableCheck(p+"DisarmOnRestart")) DisarmOnRestart = GlobalVariableGet(p+"DisarmOnRestart") > 0.5;
   EnableBridgeMode      = GlobalVariableGet(p+"EnableBridgeMode")     > 0.5;
   EnableBotAPIMode      = GlobalVariableGet(p+"EnableBotAPIMode")     > 0.5;
   EnableDiscordMode     = GlobalVariableGet(p+"EnableDiscordMode")    > 0.5;
   // CopierMode loaded below
   CopierMode            = (ENUM_COPIER_MODE)(int)GlobalVariableGet(p+"CopierMode");
   if(GlobalVariableCheck(p+"CopierAutoClose"))        CopierAutoClose = GlobalVariableGet(p+"CopierAutoClose") > 0.5;
   if(GlobalVariableCheck(p+"EnableReportLog"))        EnableReportLog = GlobalVariableGet(p+"EnableReportLog") > 0.5;
   EnableTelegramSend    = GlobalVariableGet(p+"EnableTelegramSend")   > 0.5;
   if(GlobalVariableCheck(p+"UseSeparateSendBot"))     UseSeparateSendBot = GlobalVariableGet(p+"UseSeparateSendBot") > 0.5;
   CopySL                = GlobalVariableGet(p+"CopySL")               > 0.5;
   CopyTP                = GlobalVariableGet(p+"CopyTP")               > 0.5;
   ReverseSignal         = GlobalVariableGet(p+"ReverseSignal")        > 0.5;
   EnableMultiTP         = GlobalVariableGet(p+"EnableMultiTP")        > 0.5;
   EnablePendingOrders   = GlobalVariableGet(p+"EnablePendingOrders")  > 0.5;
   EnablePendingExpiry   = GlobalVariableGet(p+"EnablePendingExpiry")  > 0.5;
   EnablePendingMultiTP  = GlobalVariableGet(p+"EnablePendingMultiTP") > 0.5;
   EnableDuplicateFilter = GlobalVariableGet(p+"EnableDuplicateFilter") > 0.5;
   if(GlobalVariableCheck(p+"DuplicateWindowMin")) DuplicateWindowMinutes = MathMax(1, (int)GlobalVariableGet(p+"DuplicateWindowMin"));
   EnableTrailingStop    = GlobalVariableGet(p+"EnableTrailingStop")   > 0.5;
   EnablePartialClose    = GlobalVariableGet(p+"EnablePartialClose")   > 0.5;
   EnableAutoSL          = GlobalVariableGet(p+"EnableAutoSL")         > 0.5;
   EnableAutoTP          = GlobalVariableGet(p+"EnableAutoTP")         > 0.5;
   if(GlobalVariableCheck(p+"EnableNewsPause"))       EnableNewsPause       = GlobalVariableGet(p+"EnableNewsPause") > 0.5;
   if(GlobalVariableCheck(p+"NewsPauseHighImpact"))   NewsPauseHighImpact   = GlobalVariableGet(p+"NewsPauseHighImpact") > 0.5;
   if(GlobalVariableCheck(p+"NewsPauseMediumImpact")) NewsPauseMediumImpact = GlobalVariableGet(p+"NewsPauseMediumImpact") > 0.5;
   if(GlobalVariableCheck(p+"EnableWhitelist"))       EnableWhitelist = GlobalVariableGet(p+"EnableWhitelist") > 0.5;
   if(GlobalVariableCheck(p+"EnableBlacklist"))       EnableBlacklist = GlobalVariableGet(p+"EnableBlacklist") > 0.5;
   if(GlobalVariableCheck(p+"EnableSkipKeywords"))    EnableSkipKeywords = GlobalVariableGet(p+"EnableSkipKeywords") > 0.5;
   EnableTimeFilter      = GlobalVariableGet(p+"EnableTimeFilter")     > 0.5;
   EnableSpreadFilter    = GlobalVariableGet(p+"EnableSpreadFilter")   > 0.5;
   if(GlobalVariableCheck(p+"EnableSlippageFilter"))  EnableSlippageFilter = GlobalVariableGet(p+"EnableSlippageFilter") > 0.5;
   RequireEntryArmour    = GlobalVariableGet(p+"RequireEntryArmour")   > 0.5;
   if(GlobalVariableCheck(p+"ModifySLTPIfPositionExists")) ModifySLTPIfPositionExists = GlobalVariableGet(p+"ModifySLTPIfPositionExists") > 0.5;
   SkipSignalWithoutSL   = GlobalVariableGet(p+"SkipSignalWithoutSL")  > 0.5;
   SkipSignalWithoutTP   = GlobalVariableGet(p+"SkipSignalWithoutTP")  > 0.5;
   if(GlobalVariableCheck(p+"EnableSignalTP")) EnableSignalTP = GlobalVariableGet(p+"EnableSignalTP") > 0.5;
   AllowSLTPModDuringCooldown = GlobalVariableGet(p+"AllowSLTPModDuringCooldown") > 0.5;
   EnableCommandReplies  = GlobalVariableGet(p+"EnableCommandReplies") > 0.5;
   EnableKeywordReplace  = GlobalVariableGet(p+"EnableKeywordReplace") > 0.5;
   EnableCustomSLTPKeywords = GlobalVariableGet(p+"EnableCustomSLTPKeywords") > 0.5;
   if(GlobalVariableCheck(p+"EnablePartialAlerts")) EnablePartialAlerts = GlobalVariableGet(p+"EnablePartialAlerts") > 0.5;
   PartialMoveSLBreakeven = GlobalVariableGet(p+"PartialMoveSLBreakeven") > 0.5;
   PartialMoveSLToTP1    = GlobalVariableGet(p+"PartialMoveSLToTP1")   > 0.5;
   if(GlobalVariableCheck(p+"PartialMoveSLToTP2")) PartialMoveSLToTP2 = GlobalVariableGet(p+"PartialMoveSLToTP2") > 0.5;
   if(GlobalVariableCheck(p+"PartialMoveSLToTP3")) PartialMoveSLToTP3 = GlobalVariableGet(p+"PartialMoveSLToTP3") > 0.5;
   if(GlobalVariableCheck(p+"SignalTpFixedOverrideMainLots")) SignalTpFixedOverrideMainLots = GlobalVariableGet(p+"SignalTpFixedOverrideMainLots") > 0.5;
   if(GlobalVariableCheck(p+"SignalTpAllocMode"))  SignalTpAllocMode = (ENUM_PARTIAL_MODE)(int)GlobalVariableGet(p+"SignalTpAllocMode");
   TGMoveSLBreakevenTP1  = GlobalVariableGet(p+"TGMoveSLBreakevenTP1") > 0.5;
   TGMoveSLToTP1OnTP2    = GlobalVariableGet(p+"TGMoveSLToTP1OnTP2")  > 0.5;
   TrailMoveToBreakeven  = GlobalVariableGet(p+"TrailMoveToBreakeven") > 0.5;
    if(GlobalVariableCheck(p+"PropFirmMode"))         PropFirmMode = GlobalVariableGet(p+"PropFirmMode") > 0.5;
   if(GlobalVariableCheck(p+"EnableDiagLog"))         EnableDiagLog = GlobalVariableGet(p+"EnableDiagLog") > 0.5;
   if(GlobalVariableCheck(p+"EnablePopupAlerts"))     EnablePopupAlerts = GlobalVariableGet(p+"EnablePopupAlerts") > 0.5;
   if(GlobalVariableCheck(p+"EnableSoundAlerts"))     EnableSoundAlerts = GlobalVariableGet(p+"EnableSoundAlerts") > 0.5;
   if(GlobalVariableCheck(p+"EnablePushNotify"))      EnablePushNotify = GlobalVariableGet(p+"EnablePushNotify") > 0.5;
   SignalCooldownSeconds = (int)GlobalVariableGet(p+"SignalCooldownSec");
   if(GlobalVariableCheck(p+"MaxTradesPerMinute"))    MaxTradesPerMinute = (int)GlobalVariableGet(p+"MaxTradesPerMinute");
   MaxLotSize            = GlobalVariableGet(p+"MaxLotSize");
   FixedLotSize          = GlobalVariableGet(p+"FixedLotSize");
   RiskPercent           = GlobalVariableGet(p+"RiskPercent");
   MaxOpenPositions      = (int)GlobalVariableGet(p+"MaxOpenPositions");
   LotMultiplier         = GlobalVariableGet(p+"LotMultiplier");
   if(GlobalVariableCheck(p+"MaxDailyLossPercent"))   MaxDailyLossPercent = GlobalVariableGet(p+"MaxDailyLossPercent");
   if(GlobalVariableCheck(p+"MaxDailyLossAmount"))    MaxDailyLossAmount = GlobalVariableGet(p+"MaxDailyLossAmount");
   if(GlobalVariableCheck(p+"DailyResetTimezone"))    DailyResetTimezone = (ENUM_DAILY_RESET_TZ)(int)GlobalVariableGet(p+"DailyResetTimezone");
   if(GlobalVariableCheck(p+"DailyLossUsePeakEquity")) DailyLossUsePeakEquity = GlobalVariableGet(p+"DailyLossUsePeakEquity") > 0.5;
   MaxSpreadPoints       = (int)GlobalVariableGet(p+"MaxSpreadPoints");
   BridgePollMs          = (int)GlobalVariableGet(p+"BridgePollMs");
   if(GlobalVariableCheck(p+"TelegramPollSeconds"))    TelegramPollSeconds = (int)GlobalVariableGet(p+"TelegramPollSeconds");
   if(GlobalVariableCheck(p+"BridgePort"))             BridgePort = (int)GlobalVariableGet(p+"BridgePort");
   if(GlobalVariableCheck(p+"DiscordPollSeconds"))     DiscordPollSeconds = (int)GlobalVariableGet(p+"DiscordPollSeconds");
   if(GlobalVariableCheck(p+"CopierPollMs"))           CopierPollMs = (int)GlobalVariableGet(p+"CopierPollMs");
   if(GlobalVariableCheck(p+"CopierStartupMode"))      CopierStartupCopyMode = (ENUM_STARTUP_COPY_MODE)(int)GlobalVariableGet(p+"CopierStartupMode");
   if(GlobalVariableCheck(p+"CopierLotMode"))          CopierLotMode = (ENUM_COPIER_LOT_MODE)(int)GlobalVariableGet(p+"CopierLotMode");
   if(GlobalVariableCheck(p+"CopierFixedLot"))         CopierFixedLot = GlobalVariableGet(p+"CopierFixedLot");
   if(GlobalVariableCheck(p+"CopierLotMultiplier"))    CopierLotMultiplier = GlobalVariableGet(p+"CopierLotMultiplier");
   if(GlobalVariableCheck(p+"CopierRiskPercent"))      CopierRiskPercent = GlobalVariableGet(p+"CopierRiskPercent");
   if(GlobalVariableCheck(p+"CopierMaxLot"))           CopierMaxLot = GlobalVariableGet(p+"CopierMaxLot");
   if(GlobalVariableCheck(p+"CopierMinLotToCopy"))     CopierMinimumLotToCopy = GlobalVariableGet(p+"CopierMinLotToCopy");
   if(GlobalVariableCheck(p+"CopierCommentMode"))      CopierTradeCommentMode = (ENUM_TRADE_COMMENT_MODE)(int)GlobalVariableGet(p+"CopierCommentMode");
   if(GlobalVariableCheck(p+"DefaultSLPoints"))        DefaultSLPoints = (int)GlobalVariableGet(p+"DefaultSLPoints");
   if(GlobalVariableCheck(p+"SkipIfLotOverMax"))       SkipIfLotOverMax = GlobalVariableGet(p+"SkipIfLotOverMax") > 0.5;
   if(GlobalVariableCheck(p+"SlippagePoints"))         SlippagePoints = (int)GlobalVariableGet(p+"SlippagePoints");
   if(GlobalVariableCheck(p+"EntrySlippagePips"))      EntrySlippagePips = GlobalVariableGet(p+"EntrySlippagePips");
   if(GlobalVariableCheck(p+"SlippageAction"))         SlippageAction = (ENUM_SLIPPAGE_ACTION)(int)GlobalVariableGet(p+"SlippageAction");
   if(GlobalVariableCheck(p+"OppositeAction"))         OppositeAction = (ENUM_OPPOSITE_ACTION)(int)GlobalVariableGet(p+"OppositeAction");
   if(GlobalVariableCheck(p+"PendingExpiryHours"))     PendingExpiryHours = (int)GlobalVariableGet(p+"PendingExpiryHours");
   if(GlobalVariableCheck(p+"MinPipsDistanceSameType")) MinPipsDistanceSameType = GlobalVariableGet(p+"MinPipsDistanceSameType");
   if(GlobalVariableCheck(p+"FallbackSLPips"))         FallbackSLPips = (int)GlobalVariableGet(p+"FallbackSLPips");
   if(GlobalVariableCheck(p+"FallbackTPPips"))         FallbackTPPips = (int)GlobalVariableGet(p+"FallbackTPPips");
   if(GlobalVariableCheck(p+"TrailStartPips"))         TrailStartPips = (int)GlobalVariableGet(p+"TrailStartPips");
   if(GlobalVariableCheck(p+"TrailDistancePips"))      TrailDistancePips = (int)GlobalVariableGet(p+"TrailDistancePips");
   if(GlobalVariableCheck(p+"TrailStepPips"))          TrailStepPips = (int)GlobalVariableGet(p+"TrailStepPips");
   if(GlobalVariableCheck(p+"BreakevenBufferPips"))    BreakevenBufferPips = (int)GlobalVariableGet(p+"BreakevenBufferPips");
   if(GlobalVariableCheck(p+"PartialCloseMode"))       PartialCloseMode = (ENUM_PARTIAL_MODE)(int)GlobalVariableGet(p+"PartialCloseMode");
   if(GlobalVariableCheck(p+"PartialScope"))           PartialScope = (ENUM_PARTIAL_SCOPE)(int)GlobalVariableGet(p+"PartialScope");
   if(GlobalVariableCheck(p+"PartialTP1Pips"))         PartialTP1Pips = GlobalVariableGet(p+"PartialTP1Pips");
   if(GlobalVariableCheck(p+"PartialTP1Lots"))         PartialTP1Lots = GlobalVariableGet(p+"PartialTP1Lots");
   if(GlobalVariableCheck(p+"PartialTP1Percent"))      PartialTP1Percent = GlobalVariableGet(p+"PartialTP1Percent");
   if(GlobalVariableCheck(p+"PartialTP2Pips"))         PartialTP2Pips = GlobalVariableGet(p+"PartialTP2Pips");
   if(GlobalVariableCheck(p+"PartialTP2Lots"))         PartialTP2Lots = GlobalVariableGet(p+"PartialTP2Lots");
   if(GlobalVariableCheck(p+"PartialTP2Percent"))      PartialTP2Percent = GlobalVariableGet(p+"PartialTP2Percent");
   if(GlobalVariableCheck(p+"PartialTP3Pips"))         PartialTP3Pips = GlobalVariableGet(p+"PartialTP3Pips");
   if(GlobalVariableCheck(p+"PartialTP3Lots"))         PartialTP3Lots = GlobalVariableGet(p+"PartialTP3Lots");
   if(GlobalVariableCheck(p+"PartialTP3Percent"))      PartialTP3Percent = GlobalVariableGet(p+"PartialTP3Percent");
   if(GlobalVariableCheck(p+"PartialTP4Pips"))         PartialTP4Pips = GlobalVariableGet(p+"PartialTP4Pips");
   if(GlobalVariableCheck(p+"PartialTP4Lots"))         PartialTP4Lots = GlobalVariableGet(p+"PartialTP4Lots");
   if(GlobalVariableCheck(p+"PartialTP4Percent"))      PartialTP4Percent = GlobalVariableGet(p+"PartialTP4Percent");
   if(GlobalVariableCheck(p+"PartialBEExtraPips"))     PartialBEExtraPips = (int)GlobalVariableGet(p+"PartialBEExtraPips");
   if(GlobalVariableCheck(p+"TGBreakevenExtraPips"))   TGBreakevenExtraPips = (int)GlobalVariableGet(p+"TGBreakevenExtraPips");
   if(GlobalVariableCheck(p+"MaxTPTargets"))           MaxTPTargets = (int)GlobalVariableGet(p+"MaxTPTargets");
   if(GlobalVariableCheck(p+"NewsPauseBeforeMinutes")) NewsPauseBeforeMinutes = (int)GlobalVariableGet(p+"NewsPauseBeforeMinutes");
   if(GlobalVariableCheck(p+"NewsPauseAfterMinutes"))  NewsPauseAfterMinutes = (int)GlobalVariableGet(p+"NewsPauseAfterMinutes");
   if(GlobalVariableCheck(p+"ReportPurgeDays"))        ReportPurgeDays = (int)GlobalVariableGet(p+"ReportPurgeDays");
   if(GlobalVariableCheck(p+"PanelMode"))              PanelMode = (ENUM_PANEL_MODE)(int)GlobalVariableGet(p+"PanelMode");
   // [MARTINGALE] - MG state is only restored when the unlock password is present in F7.
   // Without the password the saved MG state is wiped so MG cannot silently run after reattach.
   bool _hasMGPass = (inp_MartingalePassword == "NAVIGATOR-ADV");
   if(GlobalVariableCheck(p+"EnableMartingale"))
   {
      if(_hasMGPass)
         EnableMartingale = (GlobalVariableGet(p+"EnableMartingale") > 0.5);
      else
      {
         // No password → force MG off and clear persisted state so it cannot revive
         EnableMartingale = false;
         GlobalVariableSet(p+"EnableMartingale", 0.0);
         GlobalVariableSet(p+"MartingaleActivationTime", 0.0);
         GlobalVariableSet(p+"MG_COUNT", 0.0);
         Print("[MG] MG unlock password not present — Martingale disabled and streak cleared.");
      }
   }
   if(_hasMGPass)
   {
      if(GlobalVariableCheck(p+"MartingaleMode"))       MartingaleMode       = (int)GlobalVariableGet(p+"MartingaleMode");
      if(GlobalVariableCheck(p+"MartingaleMultiplier")) MartingaleMultiplier = GlobalVariableGet(p+"MartingaleMultiplier");
      if(GlobalVariableCheck(p+"MartingaleFixedStep"))  MartingaleFixedStep  = GlobalVariableGet(p+"MartingaleFixedStep");
      if(GlobalVariableCheck(p+"MartingaleBaseLot"))     MartingaleBaseLot    = GlobalVariableGet(p+"MartingaleBaseLot");
      if(GlobalVariableCheck(p+"MartingaleMaxSteps"))   MartingaleMaxSteps   = (int)GlobalVariableGet(p+"MartingaleMaxSteps");
      if(GlobalVariableCheck(p+"MartingaleResetOnWin")) MartingaleResetOnWin = (GlobalVariableGet(p+"MartingaleResetOnWin") > 0.5);
      if(GlobalVariableCheck(p+"MartingaleMaxLoss"))    MartingaleMaxLoss    = GlobalVariableGet(p+"MartingaleMaxLoss");
      if(GlobalVariableCheck(p+"MartingaleActivationTime"))
         g_mgActivationTime = (datetime)GlobalVariableGet(p+"MartingaleActivationTime");
      // [MARTINGALE STREAKS] Restore per-symbol streak state
      if(GlobalVariableCheck(p+"MG_COUNT"))
      {
         int _saved = (int)GlobalVariableGet(p+"MG_COUNT");
         for(int _mgi = 0; _mgi < _saved; _mgi++)
         {
            string _mgk = p + "MG_" + IntegerToString(_mgi) + "_";
            if(!GlobalVariableCheck(_mgk + "SYMLEN")) continue;
            int _slen = (int)GlobalVariableGet(_mgk + "SYMLEN");
            if(_slen <= 0 || _slen > 32) continue;
            string _sym = "";
            for(int _sc = 0; _sc < _slen; _sc++)
               _sym += ShortToString((short)GlobalVariableGet(_mgk + "SC" + IntegerToString(_sc)));
            if(StringLen(_sym) == 0) continue;
            int _idx = MG_GetOrCreate(_sym);
            if(GlobalVariableCheck(_mgk + "STREAK"))  g_mgTable[_idx].streak  = (int)GlobalVariableGet(_mgk + "STREAK");
            if(GlobalVariableCheck(_mgk + "PNL"))     g_mgTable[_idx].mgPnl   = GlobalVariableGet(_mgk + "PNL");
            if(GlobalVariableCheck(_mgk + "WINS"))    g_mgTable[_idx].wins    = (int)GlobalVariableGet(_mgk + "WINS");
            if(GlobalVariableCheck(_mgk + "LOSSES"))  g_mgTable[_idx].losses  = (int)GlobalVariableGet(_mgk + "LOSSES");
            if(GlobalVariableCheck(_mgk + "CARRY"))   g_mgTable[_idx].carry   = GlobalVariableGet(_mgk + "CARRY");
            else if(MartingaleMode == 4)              g_mgTable[_idx].carry   = MathMax(0.0, -g_mgTable[_idx].mgPnl);
            if(GlobalVariableCheck(_mgk + "RECTGT"))  g_mgTable[_idx].recTarget = GlobalVariableGet(_mgk + "RECTGT");
            Print("[MG] Restored streak for ", _sym, ": ", g_mgTable[_idx].streak,
                  " cumPnl=", DoubleToString(g_mgTable[_idx].mgPnl, 2),
                  " W=", g_mgTable[_idx].wins, " L=", g_mgTable[_idx].losses);
         }
      }
   }
   LoadStringSettings(); // restore string fields from config file
   // MG PASSWORD FINAL GATE: LoadStringSettings() may have just restored EnableMartingale=1 from
   // the saved config file. Re-apply the password check so MG cannot silently revive via the file.
   if(!_hasMGPass && EnableMartingale)
   {
      EnableMartingale = false;
      GlobalVariableSet(p+"EnableMartingale", 0.0);
      GlobalVariableSet(p+"MartingaleActivationTime", 0.0);
      GlobalVariableSet(p+"MG_COUNT", 0.0);
      Print("[MG] Config file restored MG=1 but password absent — Martingale force-disabled.");
   }
   // F7 INPUT PRIORITY: if user entered a value in F7 (non-empty), it overrides the saved config.
   // This lets re-attaching the EA with a new token in F7 always take effect.
   // If F7 is blank, the saved panel config is used (normal workflow after first setup).
   if(StringLen(inp_TelegramBotToken)  > 0) TelegramBotToken  = inp_TelegramBotToken;
   if(StringLen(inp_TelegramChatID)    > 0) TelegramChatID    = inp_TelegramChatID;
   if(StringLen(inp_DiscordWebhookURL) > 0) DiscordWebhookURL = inp_DiscordWebhookURL;
   if(StringLen(inp_SymbolSuffix)      > 0) SymbolSuffix      = inp_SymbolSuffix;
   if(StringLen(inp_CustomMappings)    > 0) CustomMappings    = inp_CustomMappings;
   if(StringLen(inp_TelegramSendTag)   > 0 && inp_TelegramSendTag != "[TCU]") TelegramSendTag = inp_TelegramSendTag;
   Print("[TCU] Settings loaded from GlobalVariables + config file (saved panel state).");
   return true;
}

void ShowScPanel(){
   SaveSettings();
   if(g_scOpen) { _ScDeleteContent(); } // Fast: only clear tab content
   else { _ScDeleteAll(); } // Full rebuild if was closed
   g_scOpen=true;
   // Header
   _R("HBG",g_scX,g_scY,SC_W,30,SC_HDC,SC_DV);
   _R("HGL",g_scX,g_scY+28,SC_W,2,SC_AC);
   _L("HIC",g_scX+8,g_scY+7,"*",SC_AC,11,"Segoe UI");
   _L("HTT",g_scX+26,g_scY+8,"Trade Copier Ultimate",SC_TC,10,"Segoe UI Bold");
   // [v6.01] Panel version label.
   _L("HVR",g_scX+210,g_scY+11,"v6.3",SC_DC,7,"Segoe UI");
   _L("HBRAND",g_scX+SC_SIDE+6,g_scY+26,"Navigator Trading Systems",C'70,75,90',6,"Segoe UI");
   _B("BSAVE",g_scX+240,g_scY+5,70,20,"SAVE",SC_AC,clrWhite,8);
   _B("BMIN",g_scX+SC_W-50,g_scY+5,22,20,"_",SC_HDC,SC_DC,10);
   _B("BCLOSE",g_scX+SC_W-26,g_scY+5,22,20,"X",SC_NG,clrWhite,10);
   _BuildSidebar();
   switch(g_scTab){
      case 0: _Tab0(); break;
      case 1: _Tab1(); break;
      case 2: _Tab2(); break;
      case 3: _Tab3(); break;
      case 4: _Tab4(); break;
      case 5: _Tab5(); break;
   }
   ChartRedraw(0);
}

// --- EVENT HANDLER (called from OnChartEvent) --------------------------------
bool _ScEvent(const int id,const long &lp,const double &dp,const string &sp){
   if(id!=CHARTEVENT_OBJECT_CLICK) return false;
   // Gear button on compact panel
   if(sp==PREFIX+"BTN_SETTINGS"){
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);
      if(g_scOpen) _ScDeleteAll(); else { g_scX=g_panelX+g_panelW+10; g_scY=g_panelY; ShowScPanel(); }
      return true;
   }
   // Close / minimize
   if(sp==SC_PFX+"BCLOSE" || sp==SC_PFX+"BMIN"){ _ScDeleteAll(); return true; }
   // Save button - reads ALL edit fields into shadow variables
   if(sp==SC_PFX+"BSAVE"){
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);
      _ApplyEdits();
      SaveSettings();
      Alert("Settings saved! All changes are now active and will persist across restarts.");
      return true;
   }
   // Toggle button clicks
   if(sp==SC_PFX+"s01b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableBotAPIMode=!EnableBotAPIMode; if(EnableBotAPIMode) TCU_BotApiActivate(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"s05b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); bool was=EnableBridgeMode; EnableBridgeMode=!EnableBridgeMode; if(!was && EnableBridgeMode) TCU_BridgeActivate(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"s08b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); bool was=EnableDiscordMode; EnableDiscordMode=!EnableDiscordMode; if(!was && EnableDiscordMode) ArmDiscordSenderFresh(); else ClearDiscordSendQueue(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"s0Bb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); bool was=EnableTelegramSend; EnableTelegramSend=!EnableTelegramSend; if(!was && EnableTelegramSend) ArmTelegramSenderFresh(); else ClearTelegramSendQueue(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"s0Db"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); UseSeparateSendBot=!UseSeparateSendBot; ShowScPanel(); return true; }
   if(sp==SC_PFX+"r07b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); SkipIfLotOverMax=!SkipIfLotOverMax; ShowScPanel(); return true; }
   if(sp==SC_PFX+"r0Eb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); CopierAutoClose=!CopierAutoClose; ShowScPanel(); return true; }
   if(sp==SC_PFX+"f01b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableWhitelist=!EnableWhitelist; ShowScPanel(); return true; }
   if(sp==SC_PFX+"f03b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableBlacklist=!EnableBlacklist; ShowScPanel(); return true; }
   if(sp==SC_PFX+"f05b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableSkipKeywords=!EnableSkipKeywords; ShowScPanel(); return true; }
   if(sp==SC_PFX+"f07b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); RequireEntryArmour=!RequireEntryArmour; ShowScPanel(); return true; }
   if(sp==SC_PFX+"f08b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); SkipSignalWithoutSL=!SkipSignalWithoutSL; ShowScPanel(); return true; }
   if(sp==SC_PFX+"f09b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); SkipSignalWithoutTP=!SkipSignalWithoutTP; ShowScPanel(); return true; }
   if(sp==SC_PFX+"f10b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableTimeFilter=!EnableTimeFilter; ShowScPanel(); return true; }
   if(sp==SC_PFX+"f14b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); AllowSLTPModDuringCooldown=!AllowSLTPModDuringCooldown; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t01b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnablePendingOrders=!EnablePendingOrders; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t02b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnablePendingExpiry=!EnablePendingExpiry; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t03b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnablePendingMultiTP=!EnablePendingMultiTP; ShowScPanel(); return true; }

   if(sp==SC_PFX+"t04b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); CopySL=!CopySL; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t05b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); CopyTP=!CopyTP; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t06b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); ReverseSignal=!ReverseSignal; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t09b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableAutoSL=!EnableAutoSL; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t0Bb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableAutoTP=!EnableAutoTP; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t0Db"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableCustomSLTPKeywords=!EnableCustomSLTPKeywords; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t10b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableCommandReplies=!EnableCommandReplies; ShowScPanel(); return true; }
   if(sp==SC_PFX+"t11b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableKeywordReplace=!EnableKeywordReplace; ShowScPanel(); return true; }
   if(sp==SC_PFX+"p01b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableTrailingStop=!EnableTrailingStop; ShowScPanel(); return true; }
   if(sp==SC_PFX+"p05b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); TrailMoveToBreakeven=!TrailMoveToBreakeven; ShowScPanel(); return true; }
   if(sp==SC_PFX+"p06b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnablePartialClose=!EnablePartialClose; ShowScPanel(); return true; }
   if(sp==SC_PFX+"p10b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); PartialMoveSLBreakeven=!PartialMoveSLBreakeven; ShowScPanel(); return true; }
   if(sp==SC_PFX+"p12b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); PartialMoveSLToTP1=!PartialMoveSLToTP1; ShowScPanel(); return true; }
   if(sp==SC_PFX+"p13b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableMultiTP=!EnableMultiTP; ShowScPanel(); return true; }
   if(sp==SC_PFX+"p16b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); TGMoveSLBreakevenTP1=!TGMoveSLBreakevenTP1; ShowScPanel(); return true; }
   if(sp==SC_PFX+"p17b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); TGMoveSLToTP1OnTP2=!TGMoveSLToTP1OnTP2; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g01b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); ArmExecution=!ArmExecution; if(ArmExecution) g_botSessionStartTime=TimeGMT(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"g02b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableDuplicateFilter=!EnableDuplicateFilter; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g03b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); PropFirmMode=!PropFirmMode; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g05b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableDiagLog=!EnableDiagLog; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g07b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableSpreadFilter=!EnableSpreadFilter; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g09b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableSlippageFilter=!EnableSlippageFilter; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g0Eb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnablePopupAlerts=!EnablePopupAlerts; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g0Fb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableSoundAlerts=!EnableSoundAlerts; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g10b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnablePushNotify=!EnablePushNotify; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g10Ab"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnablePartialAlerts=!EnablePartialAlerts; ShowScPanel(); return true; }
   if(sp==SC_PFX+"g12b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); EnableReportLog=!EnableReportLog; ShowScPanel(); return true; }

      if(sp==SC_PFX+"pMb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); PartialCloseMode=(ENUM_PARTIAL_MODE)(((int)PartialCloseMode+1)%2); ShowScPanel(); return true; }
   if(sp==SC_PFX+"pSMb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); SignalTpAllocMode=(ENUM_PARTIAL_MODE)(((int)SignalTpAllocMode+1)%2); ShowScPanel(); return true; }
   // Enum cycling clicks
   if(sp==SC_PFX+"r01b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); _Cycle_LotMode(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"r0Cb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); _Cycle_CopierMode(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"r0Gb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); _Cycle_CopierStartupCopyMode(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"r10b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); _Cycle_CopierLotMode(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"r15b"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); _Cycle_CopierTradeCommentMode(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"g0Cb"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); _Cycle_SlippageAction(); ShowScPanel(); return true; }
   if(sp==SC_PFX+"g0Db"){ ObjectSetInteger(0,sp,OBJPROP_STATE,false); _Cycle_OppositeAction(); ShowScPanel(); return true; }

   // Tab switching
   for(int i=0;i<SC_TABS;i++){
      if(sp==SC_PFX+"NB"+IntegerToString(i)){
         ObjectSetInteger(0,sp,OBJPROP_STATE,false);
         if(g_scTab!=i){ g_scTab=i; ShowScPanel(); }
         return true;
      }
   }
   return false;
}


//+==================================================================+
//| Trigger Pro style canvas panel                                    |
//+==================================================================+
uint TCU_A(color c, uchar alpha = 255)
{
   return ColorToARGB(c, alpha);
}

uint TCU_Darken(uint bg, int amount = 15)
{
   uint a = (bg >> 24) & 0xFF;
   uint r = (bg >> 16) & 0xFF;
   uint g = (bg >> 8) & 0xFF;
   uint b = bg & 0xFF;
   r = (r > (uint)amount) ? r - amount : 0;
   g = (g > (uint)amount) ? g - amount : 0;
   b = (b > (uint)amount) ? b - amount : 0;
   return (a << 24) | (r << 16) | (g << 8) | b;
}

string TCU_Short(string txt, int maxLen)
{
   if(StringLen(txt) <= maxLen) return txt;
   if(maxLen <= 2) return StringSubstr(txt, 0, maxLen);
   return StringSubstr(txt, 0, maxLen - 2) + "..";
}

string TCU_OnOff(bool v)
{
   return v ? "ON" : "OFF";
}

string TCU_StatusText()
{
   if(!ArmExecution) return "DISARMED";
   if(PropFirmMode) return "PROP";
   return "ARMED";
}

color TCU_StatusColor()
{
   if(!ArmExecution) return TCUC_DNG;
   if(PropFirmMode) return TCUC_WARN;
   return TCUC_OK;
}

string TCU_BridgeStatus()
{
   if(!EnableBridgeMode) return "OFF";
   if(g_bridgeFailCount == 0) return "ONLINE";
   if(g_bridgeFailCount >= 3) return "OFFLINE";
   return "CHECK";
}

string TCU_TelegramStatus()
{
   if(!EnableBotAPIMode) return "OFF";
   if(g_telegramFailCount == 0 && g_botFirstPollDone) return "ONLINE";
   if(g_telegramFailCount >= 3) return "FAIL";
   return "WAIT";
}

bool TCU_TerminalTradingAllowed()
{
   return (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
}

bool TCU_ProgramTradingAllowed()
{
   return (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
}

bool TCU_AutoTradingAllowed()
{
   return TCU_TerminalTradingAllowed() && TCU_ProgramTradingAllowed();
}

string TCU_AutoTradingStatusText()
{
   if(!TCU_TerminalTradingAllowed()) return "MT5 OFF";
   if(!TCU_ProgramTradingAllowed()) return "EA BLOCKED";
   return "ON";
}

int TCU_EffectiveMaxOpenPositions()
{
   int limit = MaxOpenPositions;
   if(PropFirmMode && (limit == 0 || limit > 5)) limit = 5;
   return limit;
}

int TCU_EffectiveMaxTradesPerMinute()
{
   int limit = MaxTradesPerMinute;
   return limit;
}

double TCU_EffectiveMaxDailyLossPercent()
{
   double limit = MaxDailyLossPercent;
   if(PropFirmMode && (limit <= 0 || limit > 5)) limit = 5;
   return limit;
}

bool TCU_EffectiveSpreadFilterEnabled()
{
   return EnableSpreadFilter;
}

int TCU_EffectiveMaxSpreadPoints()
{
   int limit = MaxSpreadPoints;
   return limit;
}

bool TCU_CsvHasWord(string csv, string word)
{
   string s = "," + csv + ",";
   string w = word;
   StringToUpper(s);
   StringToUpper(w);
   StringReplace(s, " ", "");
   StringReplace(w, " ", "");
   return (StringFind(s, "," + w + ",") >= 0);
}

string TCU_NewsCurrencyByIndex(int idx)
{
   if(idx == 0) return "USD";
   if(idx == 1) return "EUR";
   if(idx == 2) return "GBP";
   if(idx == 3) return "JPY";
   if(idx == 4) return "AUD";
   if(idx == 5) return "CAD";
   if(idx == 6) return "CHF";
   if(idx == 7) return "NZD";
   return "";
}

bool TCU_IsCommonNewsCurrency(string cur)
{
   string c = cur;
   StringToUpper(c);
   for(int i = 0; i < 8; i++)
      if(c == TCU_NewsCurrencyByIndex(i)) return true;
   return false;
}

string TCU_CleanCurrencyCsv(string csv)
{
   string s = csv;
   StringToUpper(s);
   StringReplace(s, " ", "");
   string parts[];
   int n = StringSplit(s, ',', parts);
   string out = "";
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      if(StringLen(p) < 3) continue;
      if(TCU_CsvHasWord(out, p)) continue;
      out += (StringLen(out) > 0 ? "," : "") + p;
   }
   return out;
}

string TCU_NewsExtraCurrencies()
{
   string clean = TCU_CleanCurrencyCsv(NewsPauseCurrencies);
   string parts[];
   int n = StringSplit(clean, ',', parts);
   string out = "";
   for(int i = 0; i < n; i++)
   {
      if(TCU_IsCommonNewsCurrency(parts[i])) continue;
      out += (StringLen(out) > 0 ? "," : "") + parts[i];
   }
   return out;
}

string TCU_Trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

bool TCU_NormalizeTPExecutionModes()
{
   if((int)PartialScope < (int)PARTIAL_SCOPE_AUTO || (int)PartialScope > (int)PARTIAL_SCOPE_ALL)
   {
      PartialScope = PARTIAL_SCOPE_AUTO;
      return true;
   }
   return false;
}

bool TCU_NormalizeLotMode()
{
   if(LotMode == LOT_LEGACY_UNUSED)
   {
      LotMode = LOT_FIXED;
      Print("[INIT] Legacy Lot Multiplier mode detected. Auto-converted to Fixed mode.");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| JSON string helpers -- escape-aware so signal text containing      |
//| quotes, braces or brackets is parsed correctly.                    |
//+------------------------------------------------------------------+
// Index of the closing quote of a JSON string whose opening quote is at
// `openQuotePos`. Backslash escapes are skipped. Returns -1 if unterminated.
int TCU_JsonStrEnd(string s, int openQuotePos)
{
   int n = StringLen(s);
   for(int i = openQuotePos + 1; i < n; i++)
   {
      ushort c = StringGetCharacter(s, i);
      if(c == 92) { i++; continue; }   // backslash -- skip the escaped char
      if(c == 34) return i;            // unescaped closing quote
   }
   return -1;
}

// Decode JSON string-escape sequences (\" \\ \/ \n \r \t \b \f \uXXXX).
string TCU_JsonUnescape(string s)
{
   if(StringFind(s, "\\") < 0) return s;   // fast path -- nothing to decode
   int n = StringLen(s);
   string out = "";
   for(int i = 0; i < n; i++)
   {
      ushort c = StringGetCharacter(s, i);
      if(c != 92 || i + 1 >= n) { out += ShortToString(c); continue; }
      ushort e = StringGetCharacter(s, i + 1);
      if(e == 117 && i + 5 < n)   // \uXXXX -- consumes 6 chars
      {
         int code = 0;
         bool okHex = true;
         for(int k = 0; k < 4; k++)
         {
            ushort h = StringGetCharacter(s, i + 2 + k);
            int d = 0;
            if(h >= 48 && h <= 57)       d = h - 48;
            else if(h >= 65 && h <= 70)  d = h - 55;
            else if(h >= 97 && h <= 102) d = h - 87;
            else { okHex = false; break; }
            code = code * 16 + d;
         }
         if(okHex) { out += ShortToString((ushort)code); i += 5; continue; }
         out += "u"; i += 1; continue;
      }
      if(e == 110)      out += ShortToString((ushort)10);   // \n
      else if(e == 114) out += ShortToString((ushort)13);   // \r
      else if(e == 116) out += ShortToString((ushort)9);    // \t
      else if(e == 98)  out += ShortToString((ushort)8);    // \b
      else if(e == 102) out += ShortToString((ushort)12);   // \f
      else if(e == 34)  out += "\"";
      else if(e == 92)  out += "\\";
      else if(e == 47)  out += "/";
      else              out += ShortToString(e);
      i += 1;   // consume the escaped char; the for-loop consumes the backslash
   }
   return out;
}

string ExtractJsonFlexStr(string json, string key)
{
   string srch = "\"" + key + "\"";
   int pos = StringFind(json, srch);
   if(pos < 0) return "";
   int cPos = StringFind(json, ":", pos);
   if(cPos < 0) return "";
   int start = cPos + 1;
   int len = StringLen(json);
   while(start < len)
   {
      ushort ch = StringGetCharacter(json, start);
      if(ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
         break;
      start++;
   }
   if(start >= len) return "";
   if(StringGetCharacter(json, start) == '\"')
   {
      int qEnd = TCU_JsonStrEnd(json, start);
      if(qEnd <= start) return "";
      return TCU_JsonUnescape(StringSubstr(json, start + 1, qEnd - start - 1));
   }
   int end = start;
   while(end < len)
   {
      ushort ch2 = StringGetCharacter(json, end);
      if(ch2 == ',' || ch2 == '}' || ch2 == '\r' || ch2 == '\n')
         break;
      end++;
   }
   return TCU_Trim(StringSubstr(json, start, end - start));
}

void TCU_SetNewsExtraCurrencies(string extra)
{
   string out = "";
   for(int i = 0; i < 8; i++)
   {
      string cur = TCU_NewsCurrencyByIndex(i);
      if(TCU_CsvHasWord(NewsPauseCurrencies, cur))
         out += (StringLen(out) > 0 ? "," : "") + cur;
   }
   string cleanExtra = TCU_CleanCurrencyCsv(extra);
   if(StringLen(cleanExtra) > 0)
      out += (StringLen(out) > 0 ? "," : "") + cleanExtra;
   NewsPauseCurrencies = TCU_CleanCurrencyCsv(out);
}

void TCU_ToggleNewsCurrency(string cur)
{
   string clean = TCU_CleanCurrencyCsv(NewsPauseCurrencies);
   string parts[];
   int n = StringSplit(clean, ',', parts);
   string out = "";
   bool found = false;
   string c = cur;
   StringToUpper(c);
   for(int i = 0; i < n; i++)
   {
      if(parts[i] == c) { found = true; continue; }
      out += (StringLen(out) > 0 ? "," : "") + parts[i];
   }
   if(!found)
      out += (StringLen(out) > 0 ? "," : "") + c;
   NewsPauseCurrencies = TCU_CleanCurrencyCsv(out);
}

bool TCU_NewsAppliesToSymbol(string sym, string currency)
{
   if(StringLen(sym) == 0) return true;
   string s = sym;
   string c = currency;
   StringToUpper(s);
   StringToUpper(c);
   if(StringFind(s, c) >= 0) return true;
   if(c == "USD" && (StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0 ||
                     StringFind(s, "XAG") >= 0 || StringFind(s, "US") >= 0))
      return true;
   return false;
}

void TCU_LoadNewsCalendar()
{
   g_tcuNewsCount = 0;
   ArrayResize(g_tcuNews, 0);
   g_tcuNewsLastLoad = TimeCurrent();
   NewsPauseCurrencies = TCU_CleanCurrencyCsv(NewsPauseCurrencies);

   datetime from = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   datetime to = from + 86400 * 2;
   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, "", "");
   if(total <= 0)
   {
      Print("[NEWS] Calendar load returned ", total, ". News pause has no events loaded.");
      return;
   }

   for(int i = 0; i < total && g_tcuNewsCount < 120; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      MqlCalendarCountry country;
      if(!CalendarCountryById(ev.country_id, country)) continue;

      int impact = 0;
      if(ev.importance == CALENDAR_IMPORTANCE_HIGH) impact = 3;
      else if(ev.importance == CALENDAR_IMPORTANCE_MODERATE) impact = 2;
      else impact = 1;
      if(impact == 3 && !NewsPauseHighImpact) continue;
      if(impact == 2 && !NewsPauseMediumImpact) continue;
      if(impact < 2) continue;

      string cur = country.currency;
      StringToUpper(cur);
      if(!TCU_CsvHasWord(NewsPauseCurrencies, cur)) continue;

      ArrayResize(g_tcuNews, g_tcuNewsCount + 1);
      g_tcuNews[g_tcuNewsCount].name = ev.name;
      g_tcuNews[g_tcuNewsCount].currency = cur;
      g_tcuNews[g_tcuNewsCount].time = values[i].time;
      g_tcuNews[g_tcuNewsCount].impact = impact;
      g_tcuNewsCount++;
   }
   Print("[NEWS] Loaded ", g_tcuNewsCount, " high/medium calendar events for news pause.");
}

bool IsNewsPauseActive(string sym, bool logIt = false)
{
   g_tcuNewsLockReason = "";
   g_tcuNewsLockUntil = 0;
   if(!EnableNewsPause) return false;

   datetime now = TimeCurrent();
   if(g_tcuNewsLastLoad == 0 || now - g_tcuNewsLastLoad > 1800)
      TCU_LoadNewsCalendar();

   int beforeSec = MathMax(0, NewsPauseBeforeMinutes) * 60;
   int afterSec = MathMax(0, NewsPauseAfterMinutes) * 60;
   for(int i = 0; i < g_tcuNewsCount; i++)
   {
      if(!TCU_NewsAppliesToSymbol(sym, g_tcuNews[i].currency)) continue;
      datetime start = g_tcuNews[i].time - beforeSec;
      datetime stop = g_tcuNews[i].time + afterSec;
      if(now >= start && now <= stop)
      {
         g_tcuNewsLockUntil = stop;
         g_tcuNewsLockReason = g_tcuNews[i].currency + " " + TCU_Short(g_tcuNews[i].name, 34);
         if(logIt && now - g_tcuLastNewsLog > 30)
         {
            Print("[NEWS] Entry paused for ", sym, " until ", TimeToString(stop, TIME_MINUTES),
                  " due to ", g_tcuNewsLockReason);
            g_tcuLastNewsLog = now;
         }
         return true;
      }
   }
   return false;
}

void TCU_BlendPixel(int px, int py, uint fgClr, double alpha)
{
   if(alpha <= 0.01) return;
   if(alpha >= 0.99)
   {
      g_tcuCanvas.PixelSet(px, py, fgClr);
      return;
   }

   uint bgClr = g_tcuCanvas.PixelGet(px, py);
   double fa = ((fgClr >> 24) & 0xFF) / 255.0 * alpha;
   double fr = (fgClr >> 16) & 0xFF;
   double fg = (fgClr >> 8) & 0xFF;
   double fb = fgClr & 0xFF;
   double ba = ((bgClr >> 24) & 0xFF) / 255.0;
   double br = (bgClr >> 16) & 0xFF;
   double bg = (bgClr >> 8) & 0xFF;
   double bb = bgClr & 0xFF;
   double oa = fa + ba * (1.0 - fa);
   if(oa <= 0.0) return;

   double orr = (fr * fa + br * ba * (1.0 - fa)) / oa;
   double org = (fg * fa + bg * ba * (1.0 - fa)) / oa;
   double orb = (fb * fa + bb * ba * (1.0 - fa)) / oa;
   uint finalClr = ((uint)(oa * 255.0) << 24) | ((uint)orr << 16) | ((uint)org << 8) | (uint)orb;
   g_tcuCanvas.PixelSet(px, py, finalClr);
}

void TCU_FillRoundRectAA(int x, int y, int w, int h, int r, uint clr)
{
   if(w <= 0 || h <= 0) return;
   if(r <= 0)
   {
      g_tcuCanvas.FillRectangle(x, y, x + w - 1, y + h - 1, clr);
      return;
   }
   if(r > h / 2) r = h / 2;
   if(r > w / 2) r = w / 2;

   int x2 = x + w - 1;
   int y2 = y + h - 1;
   g_tcuCanvas.FillRectangle(x + r, y, x2 - r, y2, clr);
   g_tcuCanvas.FillRectangle(x, y + r, x + r - 1, y2 - r, clr);
   g_tcuCanvas.FillRectangle(x2 - r + 1, y + r, x2, y2 - r, clr);

   for(int cy = 0; cy < r; cy++)
   {
      for(int cx = 0; cx < r; cx++)
      {
         double dx = (r - 0.5) - (cx + 0.5);
         double dy = (r - 0.5) - (cy + 0.5);
         double dist = MathSqrt(dx * dx + dy * dy);
         double alpha = 1.0;
         if(dist > r) alpha = 0.0;
         else if(dist > r - 1.0) alpha = r - dist;
         if(alpha > 0)
         {
            TCU_BlendPixel(x + cx, y + cy, clr, alpha);
            TCU_BlendPixel(x2 - cx, y + cy, clr, alpha);
            TCU_BlendPixel(x + cx, y2 - cy, clr, alpha);
            TCU_BlendPixel(x2 - cx, y2 - cy, clr, alpha);
         }
      }
   }
}

void TCU_Text(int x, int y, string txt, uint clr, int sz = 9, string font = "Segoe UI")
{
   int useSz = (sz < 8) ? sz + 1 : sz;
   string useFont = (font == "Segoe UI" && sz < 8) ? "Segoe UI Semibold" : font;
   g_tcuCanvas.FontSet(useFont, -useSz * 10);
   g_tcuCanvas.TextOut(x, y, txt, clr);
}

void TCU_TextBold(int x, int y, string txt, uint clr, int sz = 9)
{
   TCU_Text(x, y, txt, clr, sz, "Segoe UI Semibold");
}

string TCU_CopierModeText()
{
   if(CopierMode == MODE_MASTER) return "MASTER";
   if(CopierMode == MODE_SLAVE) return "SLAVE";
   return "OFF";
}

string TCU_CopierLotModeText()
{
   if(CopierLotMode == COPIER_LOT_COPY_MASTER) return "COPY MASTER";
   if(CopierLotMode == COPIER_LOT_FIXED) return "FIXED LOT";
   if(CopierLotMode == COPIER_LOT_MULTIPLIER) return "MULTIPLIER";
   if(CopierLotMode == COPIER_LOT_RISK_PCT) return "RISK %";
   if(CopierLotMode == COPIER_LOT_BALANCE_PROPORTIONAL) return "BALANCE PROPORTIONAL";
   return "FIXED LOT";
}

string TCU_CopierTradeCommentModeText()
{
   if(CopierTradeCommentMode == TRADE_COMMENT_OFF) return "OFF";
   if(CopierTradeCommentMode == TRADE_COMMENT_CUSTOM) return "CUSTOM";
   return "DEFAULT";
}

string TCU_CopierStartupModeText()
{
   if(CopierStartupCopyMode == COPY_ALL_EXISTING_TRADES) return "COPY EXISTING";
   return "NEW TRADES ONLY";
}

string TCU_LotModeText()
{
   if(LotMode == LOT_FIXED) return "FIXED";
   if(LotMode == LOT_RISK_PERCENT) return "RISK %";
   return "FIXED";
}

string TCU_PartialScopeText()
{
   if(PartialScope == PARTIAL_SCOPE_ALL) return "ALL";
   return "AUTO";
}

string TCU_SlippageActionText()
{
   if(SlippageAction == SLIP_OPEN_PENDING) return "OPEN PENDING";
   return "SKIP SIGNAL";
}

string TCU_OppositeActionText()
{
   if(OppositeAction == OPP_CLOSE_OPPOSITE) return "CLOSE OPPOSITE";
   if(OppositeAction == OPP_CLOSE_ALL) return "CLOSE ALL";
   return "DO NOTHING";
}

string TCU_TradeComment(string commentText)
{
   return PropFirmMode ? "" : commentText;
}

string TCU_CopierTradeComment(string defaultComment)
{
   if(PropFirmMode) return "";
   if(CopierTradeCommentMode == TRADE_COMMENT_OFF) return "";
   if(CopierTradeCommentMode == TRADE_COMMENT_CUSTOM) return CopierCustomTradeComment;
   return defaultComment;
}

string TCU_CopierMetaFileName()
{
   return CopierFileName + ".meta";
}

void TCU_WriteMasterMeta()
{
   int handle = FileOpen(TCU_CopierMetaFileName(), FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(handle, "MasterBalance", "MasterEquity", "Time");
   FileWrite(handle, AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY), TimeCurrent());
   FileClose(handle);
}

double TCU_ReadMasterBalanceMeta()
{
   int handle = FileOpen(TCU_CopierMetaFileName(), FILE_READ|FILE_CSV|FILE_COMMON|FILE_SHARE_WRITE|FILE_SHARE_READ, ',');
   if(handle == INVALID_HANDLE)
      return 0.0;

   while(!FileIsEnding(handle))
   {
      FileReadString(handle);
      if(FileIsLineEnding(handle)) break;
   }

   double masterBalance = 0.0;
   if(!FileIsEnding(handle))
      masterBalance = StringToDouble(FileReadString(handle));

   FileClose(handle);
   return masterBalance;
}

bool IsExcludedPositionTicket(ulong ticket, ulong &excludeTickets[])
{
   if(ticket == 0) return true;
   int n = ArraySize(excludeTickets);
   for(int i = 0; i < n; i++)
      if(excludeTickets[i] == ticket)
         return true;
   return false;
}

ulong ResolvePositionTicketFromTradeResultEx(string sym, ENUM_POSITION_TYPE posType, ulong orderTicket, ulong dealTicket,
                                            ulong &excludeTickets[])
{
   if(orderTicket > 0 && PositionSelectByTicket(orderTicket) && !IsExcludedPositionTicket(orderTicket, excludeTickets))
      return orderTicket;

   ulong positionId = 0;
   if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

   ulong bestTicket = 0;
   long bestTime = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string posSym = PositionGetString(POSITION_SYMBOL);
      if(posSym != sym) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ulong posIdentifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(positionId > 0 && posIdentifier == positionId && !IsExcludedPositionTicket(ticket, excludeTickets))
         return ticket;

      long posTime = (long)PositionGetInteger(POSITION_TIME_MSC);
      if(!IsExcludedPositionTicket(ticket, excludeTickets) && posTime >= bestTime)
      {
         bestTime = posTime;
         bestTicket = ticket;
      }
   }

   return bestTicket;
}

ulong ResolvePositionTicketFromTradeResult(string sym, ENUM_POSITION_TYPE posType, ulong orderTicket, ulong dealTicket)
{
   ulong excludeTickets[];
   return ResolvePositionTicketFromTradeResultEx(sym, posType, orderTicket, dealTicket, excludeTickets);
}

ulong WaitForUniquePositionTicketFromTradeResult(string sym, ENUM_POSITION_TYPE posType, ulong orderTicket, ulong dealTicket,
                                                ulong &excludeTickets[], int timeoutMs = 1500)
{
   ulong started = GetTickCount64();
   while(true)
   {
      ulong ticket = ResolvePositionTicketFromTradeResultEx(sym, posType, orderTicket, dealTicket, excludeTickets);
      if(ticket > 0)
         return ticket;
      if((int)(GetTickCount64() - started) >= timeoutMs)
         break;
      Sleep(50);
   }
   return 0;
}

void QueuePendingSLTPAttach(string sym, ENUM_POSITION_TYPE posType, ulong orderTicket, ulong dealTicket,
                            ulong liveTicket, double sl, double tp, string context)
{
   if(sl <= 0 && tp <= 0) return;
   int i = g_sltpQueueCount;
   g_sltpQueueCount++;
   ArrayResize(g_sltpOrderTickets, g_sltpQueueCount);
   ArrayResize(g_sltpDealTickets, g_sltpQueueCount);
   ArrayResize(g_sltpLiveTickets, g_sltpQueueCount);
   ArrayResize(g_sltpSymbols, g_sltpQueueCount);
   ArrayResize(g_sltpPosTypes, g_sltpQueueCount);
   ArrayResize(g_sltpSLs, g_sltpQueueCount);
   ArrayResize(g_sltpTPs, g_sltpQueueCount);
   ArrayResize(g_sltpContexts, g_sltpQueueCount);
   ArrayResize(g_sltpAttempts, g_sltpQueueCount);
   ArrayResize(g_sltpQueuedAt, g_sltpQueueCount);

   g_sltpOrderTickets[i] = orderTicket;
   g_sltpDealTickets[i] = dealTicket;
   g_sltpLiveTickets[i] = liveTicket;
   g_sltpSymbols[i] = sym;
   g_sltpPosTypes[i] = (int)posType;
   g_sltpSLs[i] = sl;
   g_sltpTPs[i] = tp;
   g_sltpContexts[i] = context;
   g_sltpAttempts[i] = 0;
   g_sltpQueuedAt[i] = GetTickCount64();
   Print("[SLTP-RETRY] Queued attach for ", context, " ", sym, " order=", orderTicket, " deal=", dealTicket, " ticket=", liveTicket);
}

int TCU_AttachExtraFloorPoints(string sym)
{
   string u = sym; StringToUpper(u);
   if(StringFind(u, "BTC") >= 0) return 2500;
   if(StringFind(u, "ETH") >= 0) return 600;
   if(StringFind(u, "XAU") >= 0 || StringFind(u, "GOLD") >= 0) return 150;
   if(StringFind(u, "XAG") >= 0 || StringFind(u, "SILVER") >= 0) return 80;
   return 20;
}

bool TCU_PrepareSafeAttachLevels(string sym, ENUM_POSITION_TYPE posType, double desiredSL, double desiredTP,
                                 double &safeSL, double &safeTP, string &adjustNote)
{
   safeSL = desiredSL;
   safeTP = desiredTP;
   adjustNote = "";

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(point <= 0 || bid <= 0 || ask <= 0)
      return false;

   int stopsLevel = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   double spreadPts = (ask - bid) / point;
   double minPts = MathMax((double)(MathMax(stopsLevel, freezeLevel) + 5),
                           MathMax(spreadPts * 3.0, (double)TCU_AttachExtraFloorPoints(sym)));
   double minDist = minPts * point;

   if(posType == POSITION_TYPE_BUY)
   {
      if(safeSL > 0)
      {
         double maxSL = NormalizeDouble(bid - minDist, digits);
         if(safeSL > maxSL)
         {
            safeSL = maxSL;
            adjustNote += "SL widened; ";
         }
      }
      if(safeTP > 0)
      {
         // Drop TP entirely if it is on the wrong side of current price (BUY TP must be above ask)
         if(safeTP <= bid)
         {
            safeTP = 0;
            adjustNote += "TP dropped (wrong side); ";
         }
         else
         {
            double minTP = NormalizeDouble(ask + minDist, digits);
            if(safeTP < minTP)
            {
               safeTP = minTP;
               adjustNote += "TP widened; ";
            }
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(safeSL > 0)
      {
         double minSL = NormalizeDouble(ask + minDist, digits);
         if(safeSL < minSL)
         {
            safeSL = minSL;
            adjustNote += "SL widened; ";
         }
      }
      if(safeTP > 0)
      {
         // Drop TP entirely if it is on the wrong side of current price (SELL TP must be below bid)
         if(safeTP >= ask)
         {
            safeTP = 0;
            adjustNote += "TP dropped (wrong side); ";
         }
         else
         {
            double maxTP = NormalizeDouble(bid - minDist, digits);
            if(safeTP > maxTP)
            {
               safeTP = maxTP;
               adjustNote += "TP widened; ";
            }
         }
      }
   }

   return true;
}

void RemovePendingSLTPAttach(int idx)
{
   if(idx < 0 || idx >= g_sltpQueueCount) return;
   for(int i = idx; i < g_sltpQueueCount - 1; i++)
   {
      g_sltpOrderTickets[i] = g_sltpOrderTickets[i + 1];
      g_sltpDealTickets[i] = g_sltpDealTickets[i + 1];
      g_sltpLiveTickets[i] = g_sltpLiveTickets[i + 1];
      g_sltpSymbols[i] = g_sltpSymbols[i + 1];
      g_sltpPosTypes[i] = g_sltpPosTypes[i + 1];
      g_sltpSLs[i] = g_sltpSLs[i + 1];
      g_sltpTPs[i] = g_sltpTPs[i + 1];
      g_sltpContexts[i] = g_sltpContexts[i + 1];
      g_sltpAttempts[i] = g_sltpAttempts[i + 1];
      g_sltpQueuedAt[i] = g_sltpQueuedAt[i + 1];
   }
   g_sltpQueueCount--;
   ArrayResize(g_sltpOrderTickets, g_sltpQueueCount);
   ArrayResize(g_sltpDealTickets, g_sltpQueueCount);
   ArrayResize(g_sltpLiveTickets, g_sltpQueueCount);
   ArrayResize(g_sltpSymbols, g_sltpQueueCount);
   ArrayResize(g_sltpPosTypes, g_sltpQueueCount);
   ArrayResize(g_sltpSLs, g_sltpQueueCount);
   ArrayResize(g_sltpTPs, g_sltpQueueCount);
   ArrayResize(g_sltpContexts, g_sltpQueueCount);
   ArrayResize(g_sltpAttempts, g_sltpQueueCount);
   ArrayResize(g_sltpQueuedAt, g_sltpQueueCount);
}

void ProcessPendingSLTPAttaches()
{
   if(g_sltpQueueCount == 0) return;
   ulong now = GetTickCount64();
   for(int i = g_sltpQueueCount - 1; i >= 0; i--)
   {
      ulong age = now - g_sltpQueuedAt[i];
      if(g_sltpAttempts[i] >= 25 || age > 15000)
      {
         Print("[SLTP-RETRY] Giving up on ", g_sltpContexts[i], " ", g_sltpSymbols[i],
               " after attempts=", g_sltpAttempts[i], " ageMs=", age);
         RemovePendingSLTPAttach(i);
         continue;
      }

      ulong liveTicket = g_sltpLiveTickets[i];
      if(!(liveTicket > 0 && PositionSelectByTicket(liveTicket)))
      {
         liveTicket = ResolvePositionTicketFromTradeResult(
            g_sltpSymbols[i],
            (ENUM_POSITION_TYPE)g_sltpPosTypes[i],
            g_sltpOrderTickets[i],
            g_sltpDealTickets[i]
         );
      }

      if(!(liveTicket > 0 && PositionSelectByTicket(liveTicket)))
      {
         g_sltpAttempts[i]++;
         continue;
      }

      g_sltpLiveTickets[i] = liveTicket;
      int digits = (int)SymbolInfoInteger(g_sltpSymbols[i], SYMBOL_DIGITS);
      double wantSL = g_sltpSLs[i] > 0 ? NormalizeDouble(g_sltpSLs[i], digits) : 0;
      double wantTP = g_sltpTPs[i] > 0 ? NormalizeDouble(g_sltpTPs[i], digits) : 0;
      string adjustNote = "";
      // Recompute safe levels from the original queued request each retry so
      // widening does not drift further away from the signal over time.
      TCU_PrepareSafeAttachLevels(g_sltpSymbols[i], (ENUM_POSITION_TYPE)g_sltpPosTypes[i], wantSL, wantTP, wantSL, wantTP, adjustNote);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      bool slDone = (wantSL <= 0) || MathAbs(curSL - wantSL) < (MathPow(10.0, -digits) * 0.5);
      bool tpDone = (wantTP <= 0) || MathAbs(curTP - wantTP) < (MathPow(10.0, -digits) * 0.5);
      if(slDone && tpDone)
      {
         RemovePendingSLTPAttach(i);
         continue;
      }

      if(g_trade.PositionModify(liveTicket, wantSL, wantTP))
      {
         Print("[SLTP-RETRY] Attached SL/TP for ", g_sltpContexts[i], " ", g_sltpSymbols[i], " ticket=", liveTicket,
               (StringLen(adjustNote) > 0 ? " | adjusted: " + adjustNote : ""));
         RemovePendingSLTPAttach(i);
      }
      else
      {
         g_sltpAttempts[i]++;
      }
   }
}

void TCU_RegHit(string name, int x, int y, int w, int h)
{
   ArrayResize(g_tcuHits, g_tcuHitCount + 1);
   g_tcuHits[g_tcuHitCount].name = name;
   g_tcuHits[g_tcuHitCount].x = x;
   g_tcuHits[g_tcuHitCount].y = y;
   g_tcuHits[g_tcuHitCount].w = w;
   g_tcuHits[g_tcuHitCount].h = h;
   g_tcuHitCount++;
}

string TCU_HitTest(int mx, int my)
{
   for(int i = g_tcuHitCount - 1; i >= 0; i--)
   {
      if(mx >= g_tcuHits[i].x && mx < g_tcuHits[i].x + g_tcuHits[i].w
         && my >= g_tcuHits[i].y && my < g_tcuHits[i].y + g_tcuHits[i].h)
         return g_tcuHits[i].name;
   }
   return "";
}

string TCU_TicketText(ulong ticket)
{
   return StringFormat("%I64u", ticket);
}

void TCU_MonRegHit(string name, int x, int y, int w, int h)
{
   ArrayResize(g_tcuMonHits, g_tcuMonHitCount + 1);
   g_tcuMonHits[g_tcuMonHitCount].name = name;
   g_tcuMonHits[g_tcuMonHitCount].x = x;
   g_tcuMonHits[g_tcuMonHitCount].y = y;
   g_tcuMonHits[g_tcuMonHitCount].w = w;
   g_tcuMonHits[g_tcuMonHitCount].h = h;
   g_tcuMonHitCount++;
}

string TCU_MonHitTest(int mx, int my)
{
   for(int i = g_tcuMonHitCount - 1; i >= 0; i--)
   {
      if(mx >= g_tcuMonHits[i].x && mx < g_tcuMonHits[i].x + g_tcuMonHits[i].w
         && my >= g_tcuMonHits[i].y && my < g_tcuMonHits[i].y + g_tcuMonHits[i].h)
         return g_tcuMonHits[i].name;
   }
   return "";
}

void TCU_MonFillRoundRect(int x, int y, int w, int h, int r, uint clr)
{
   if(r <= 0)
   {
      g_tcuMonCanvas.FillRectangle(x, y, x + w - 1, y + h - 1, clr);
      return;
   }
   int x2 = x + w - 1;
   int y2 = y + h - 1;
   g_tcuMonCanvas.FillRectangle(x + r, y, x2 - r, y2, clr);
   g_tcuMonCanvas.FillRectangle(x, y + r, x + r - 1, y2 - r, clr);
   g_tcuMonCanvas.FillRectangle(x2 - r + 1, y + r, x2, y2 - r, clr);
   g_tcuMonCanvas.FillCircle(x + r, y + r, r, clr);
   g_tcuMonCanvas.FillCircle(x2 - r, y + r, r, clr);
   g_tcuMonCanvas.FillCircle(x + r, y2 - r, r, clr);
   g_tcuMonCanvas.FillCircle(x2 - r, y2 - r, r, clr);
}

void TCU_MonText(int x, int y, string txt, uint clr, int sz = 8, string font = "Segoe UI")
{
   g_tcuMonCanvas.FontSet(font, -sz * 10);
   g_tcuMonCanvas.TextOut(x, y, txt, clr);
}

void TCU_MonTextBold(int x, int y, string txt, uint clr, int sz = 8)
{
   TCU_MonText(x, y, txt, clr, sz, "Segoe UI Semibold");
}

void TCU_MonBtn(string name, int x, int y, int w, int h, string txt, uint bg, uint fg, int sz = 7, int r = 4)
{
   int offset = (name == g_tcuMonPressed && name != "") ? 1 : 0;
   if(offset > 0)
      bg = TCU_Darken(bg, 15);
   TCU_MonFillRoundRect(x, y + offset, w, h, r, bg);
   g_tcuMonCanvas.FontSet("Segoe UI Semibold", -sz * 10);
   int tw = 0, th = 0;
   g_tcuMonCanvas.TextSize(txt, tw, th);
   g_tcuMonCanvas.TextOut(x + (w - tw) / 2, y + offset + (h - th) / 2, txt, fg);
   TCU_MonRegHit(name, x, y, w, h);
}

// [v6.00 NEW][PerSymUI] Per-Symbol Lots modal canvas helpers (clones of TCU_Mon* family).
// Kept separate so the two popups can be open simultaneously without canvas/hit-buffer collisions.
void TCU_PslRegHit(string name, int x, int y, int w, int h)
{
   ArrayResize(g_tcuPslHits, g_tcuPslHitCount + 1);
   g_tcuPslHits[g_tcuPslHitCount].name = name;
   g_tcuPslHits[g_tcuPslHitCount].x = x;
   g_tcuPslHits[g_tcuPslHitCount].y = y;
   g_tcuPslHits[g_tcuPslHitCount].w = w;
   g_tcuPslHits[g_tcuPslHitCount].h = h;
   g_tcuPslHitCount++;
}

string TCU_PslHitTest(int mx, int my)
{
   for(int i = g_tcuPslHitCount - 1; i >= 0; i--)
   {
      if(mx >= g_tcuPslHits[i].x && mx < g_tcuPslHits[i].x + g_tcuPslHits[i].w
         && my >= g_tcuPslHits[i].y && my < g_tcuPslHits[i].y + g_tcuPslHits[i].h)
         return g_tcuPslHits[i].name;
   }
   return "";
}

void TCU_PslFillRoundRect(int x, int y, int w, int h, int r, uint clr)
{
   if(r <= 0)
   {
      g_tcuPslCanvas.FillRectangle(x, y, x + w - 1, y + h - 1, clr);
      return;
   }
   int x2 = x + w - 1;
   int y2 = y + h - 1;
   g_tcuPslCanvas.FillRectangle(x + r, y, x2 - r, y2, clr);
   g_tcuPslCanvas.FillRectangle(x, y + r, x + r - 1, y2 - r, clr);
   g_tcuPslCanvas.FillRectangle(x2 - r + 1, y + r, x2, y2 - r, clr);
   g_tcuPslCanvas.FillCircle(x + r, y + r, r, clr);
   g_tcuPslCanvas.FillCircle(x2 - r, y + r, r, clr);
   g_tcuPslCanvas.FillCircle(x + r, y2 - r, r, clr);
   g_tcuPslCanvas.FillCircle(x2 - r, y2 - r, r, clr);
}

void TCU_PslText(int x, int y, string txt, uint clr, int sz = 8, string font = "Segoe UI")
{
   g_tcuPslCanvas.FontSet(font, -sz * 10);
   g_tcuPslCanvas.TextOut(x, y, txt, clr);
}

void TCU_PslTextBold(int x, int y, string txt, uint clr, int sz = 8)
{
   TCU_PslText(x, y, txt, clr, sz, "Segoe UI Semibold");
}

void TCU_PslBtn(string name, int x, int y, int w, int h, string txt, uint bg, uint fg, int sz = 7, int r = 4, bool enabled = true)
{
   int offset = (name == g_tcuPslPressed && name != "" && enabled) ? 1 : 0;
   uint drawBg = bg;
   if(offset > 0) drawBg = TCU_Darken(drawBg, 15);
   if(!enabled)   drawBg = TCU_Darken(drawBg, 50);
   TCU_PslFillRoundRect(x, y + offset, w, h, r, drawBg);
   g_tcuPslCanvas.FontSet("Segoe UI Semibold", -sz * 10);
   int tw = 0, th = 0;
   g_tcuPslCanvas.TextSize(txt, tw, th);
   uint drawFg = enabled ? fg : TCU_Darken(fg, 50);
   g_tcuPslCanvas.TextOut(x + (w - tw) / 2, y + offset + (h - th) / 2, txt, drawFg);
   if(enabled) TCU_PslRegHit(name, x, y, w, h);
}

// [MG Monitor] Canvas helpers -- separate canvas/hit-buffer so it can coexist with Trade Monitor + PSL popups.
void TCU_MGMRegHit(string name, int x, int y, int w, int h)
{
   ArrayResize(g_mgmHits, g_mgmHitCount + 1);
   g_mgmHits[g_mgmHitCount].name = name;
   g_mgmHits[g_mgmHitCount].x = x;
   g_mgmHits[g_mgmHitCount].y = y;
   g_mgmHits[g_mgmHitCount].w = w;
   g_mgmHits[g_mgmHitCount].h = h;
   g_mgmHitCount++;
}

string TCU_MGMHitTest(int mx, int my)
{
   for(int i = g_mgmHitCount - 1; i >= 0; i--)
      if(mx >= g_mgmHits[i].x && mx < g_mgmHits[i].x + g_mgmHits[i].w
         && my >= g_mgmHits[i].y && my < g_mgmHits[i].y + g_mgmHits[i].h)
         return g_mgmHits[i].name;
   return "";
}

void TCU_MGMBlendPixel(int px, int py, uint fgClr, double alpha)
{
   if(alpha <= 0.01) return;
   if(alpha >= 0.99) { g_mgmCanvas.PixelSet(px, py, fgClr); return; }
   uint bgClr = g_mgmCanvas.PixelGet(px, py);
   double fa = ((fgClr >> 24) & 0xFF) / 255.0 * alpha;
   double fr = (fgClr >> 16) & 0xFF;
   double fg = (fgClr >> 8)  & 0xFF;
   double fb =  fgClr        & 0xFF;
   double ba = ((bgClr >> 24) & 0xFF) / 255.0;
   double br = (bgClr >> 16) & 0xFF;
   double bg = (bgClr >> 8)  & 0xFF;
   double bb =  bgClr        & 0xFF;
   double oa = fa + ba * (1.0 - fa);
   if(oa <= 0.0) return;
   double orr = (fr * fa + br * ba * (1.0 - fa)) / oa;
   double org = (fg * fa + bg * ba * (1.0 - fa)) / oa;
   double orb = (fb * fa + bb * ba * (1.0 - fa)) / oa;
   g_mgmCanvas.PixelSet(px, py, ((uint)(oa*255.0) << 24) | ((uint)orr << 16) | ((uint)org << 8) | (uint)orb);
}
void TCU_MGMFillRoundRect(int x, int y, int w, int h, int r, uint clr)
{
   if(w <= 0 || h <= 0) return;
   if(r <= 0) { g_mgmCanvas.FillRectangle(x, y, x+w-1, y+h-1, clr); return; }
   if(r > h/2) r = h/2;
   if(r > w/2) r = w/2;
   int x2 = x+w-1, y2 = y+h-1;
   g_mgmCanvas.FillRectangle(x+r,   y,    x2-r,  y2,   clr);
   g_mgmCanvas.FillRectangle(x,     y+r,  x+r-1, y2-r, clr);
   g_mgmCanvas.FillRectangle(x2-r+1,y+r,  x2,    y2-r, clr);
   for(int cy = 0; cy < r; cy++)
   {
      for(int cx = 0; cx < r; cx++)
      {
         double dx = (r - 0.5) - (cx + 0.5);
         double dy = (r - 0.5) - (cy + 0.5);
         double dist = MathSqrt(dx*dx + dy*dy);
         double alpha = (dist > r) ? 0.0 : (dist > r-1.0) ? r-dist : 1.0;
         if(alpha > 0)
         {
            TCU_MGMBlendPixel(x  + cx, y  + cy, clr, alpha);
            TCU_MGMBlendPixel(x2 - cx, y  + cy, clr, alpha);
            TCU_MGMBlendPixel(x  + cx, y2 - cy, clr, alpha);
            TCU_MGMBlendPixel(x2 - cx, y2 - cy, clr, alpha);
         }
      }
   }
}

void TCU_MGMText(int x, int y, string txt, uint clr, int sz = 8, string font = "Segoe UI")
{
   int useSz = (sz < 8) ? sz + 1 : sz;
   string useFont = (font == "Segoe UI" && sz < 8) ? "Segoe UI Semibold" : font;
   g_mgmCanvas.FontSet(useFont, -useSz * 10);
   g_mgmCanvas.TextOut(x, y, txt, clr);
}

void TCU_MGMTextBold(int x, int y, string txt, uint clr, int sz = 8)
{
   TCU_MGMText(x, y, txt, clr, sz, "Segoe UI Semibold");
}

void TCU_MGMBtn(string name, int x, int y, int w, int h, string txt, uint bg, uint fg, int sz = 7, int r = 4)
{
   int offset = (name == g_mgmPressed && name != "") ? 1 : 0;
   if(offset > 0) bg = TCU_Darken(bg, 15);
   TCU_MGMFillRoundRect(x, y+offset, w, h, r, bg);
   g_mgmCanvas.FontSet("Segoe UI Semibold", -sz * 10);
   int tw = 0, th = 0;
   g_mgmCanvas.TextSize(txt, tw, th);
   g_mgmCanvas.TextOut(x+(w-tw)/2, y+offset+(h-th)/2, txt, fg);
   TCU_MGMRegHit(name, x, y, w, h);
}

// [v6.00 NEW][PerSymUI] OBJ_EDIT placed at modal-relative coordinates (offset by
// g_tcuPslX/Y instead of g_panelX/Y). Used for the in-modal "Add symbol" input.
void TCU_PslEditBox(string key, int x, int y, int w, int h, string value)
{
   string name = TCUC_PFX + "ED_" + key;
   TCU_RegisterEdit(name);
   bool created = (ObjectFind(0, name) < 0);
   if(created)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      // [v6.01 FIX] one-time static props -- see TCU_EditRow comment for why.
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'31,52,82');
      ObjectSetInteger(0, name, OBJPROP_COLOR, C'0,217,181');
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, TCUC_GRID);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 25);
   }
   TCU_PositionEdit(name, g_tcuPslX + x, g_tcuPslY + y, w, h);
   TCU_SetEditText(name, value);
}

bool TCU_IsPartialTrackedTicket(ulong ticket)
{
   for(int i = 0; i < g_partialCount; i++)
      if(g_partialTickets[i] == ticket)
         return true;
   return false;
}

bool TCU_IsMultiTPTicket(ulong ticket)
{
   for(int i = 0; i < g_mtpCount; i++)
      if(g_mtpTickets[i] == ticket)
         return true;
   return false;
}

bool TCU_IsPendingExpiryTicket(ulong ticket)
{
   int n = ArraySize(g_pendingExpTickets);
   for(int i = 0; i < n; i++)
      if(g_pendingExpTickets[i] == ticket)
         return true;
   return false;
}

string TCU_MonitorSource(string commentText)
{
   string comment = commentText;
   StringTrimLeft(comment);
   StringTrimRight(comment);
   if(StringLen(comment) == 0)
      return PropFirmMode ? "PROP / NO COMMENT" : "EA";
   int tpPos = StringFind(comment, "_TP");
   if(tpPos > 0)
      return StringSubstr(comment, 0, tpPos);
   return comment;
}

string TCU_PositionFlagsText(ulong ticket)
{
   string flags = "";
   if(TCU_IsMultiTPTicket(ticket)) flags += "MTP ";
   if(TCU_IsPartialTrackedTicket(ticket)) flags += "PART ";
   if(EnableTrailingStop) flags += "TRAIL ";
   if(TrailMoveToBreakeven || PartialMoveSLBreakeven || TGMoveSLBreakevenTP1) flags += "BE ";
   StringTrimRight(flags);
   return flags;
}

string TCU_OrderFlagsText(ulong ticket)
{
   string flags = "";
   if(TCU_IsPendingExpiryTicket(ticket)) flags += "EXP ";
   if(EnablePendingMultiTP) flags += "PMTP ";
   StringTrimRight(flags);
   return flags;
}

void TCU_Btn(string name, int x, int y, int w, int h, string txt, uint bg, uint fg, int sz = 8, int r = 5)
{
   int offset = (name == g_tcuPressed && name != "") ? 1 : 0;
   if(offset > 0)
      bg = TCU_Darken(bg, 15);

   TCU_FillRoundRectAA(x, y + offset, w, h, r, bg);
   g_tcuCanvas.FontSet("Segoe UI Semibold", -sz * 10);
   int tw = 0, th = 0;
   g_tcuCanvas.TextSize(txt, tw, th);
   g_tcuCanvas.TextOut(x + (w - tw) / 2, y + offset + (h - th) / 2, txt, fg);
   TCU_RegHit(name, x, y, w, h);
}

void TCU_InitCanvas(int width, int height)
{
   string name = TCUC_PFX + "CANVAS";
   if(g_tcuCanvasCreated)
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panelX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panelY);
      if(width != g_tcuCanvasW || height != g_tcuCanvasH)
      {
         g_tcuCanvas.Resize(width, height);
         ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
         ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
         g_tcuCanvasW = width;
         g_tcuCanvasH = height;
      }
      g_tcuCanvas.Erase(0xFF0F1219);
   }
   else
   {
      g_tcuCanvas.CreateBitmapLabel(0, 0, name, g_panelX, g_panelY, width, height, COLOR_FORMAT_ARGB_NORMALIZE);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 5);
      g_tcuCanvas.Erase(0xFF0F1219);
      g_tcuCanvasCreated = true;
      g_tcuCanvasW = width;
      g_tcuCanvasH = height;
   }
   g_tcuHitCount = 0;
}

void TCU_DestroyCanvas()
{
   TCU_DestroyMonitorPopup();
   TCU_DestroyPerSymPopup();   // [v6.00 NEW][PerSymUI]
   g_tcuPslOpen = false;
   TCU_DestroyMGMonitor();
   g_mgmOpen = false;
   TCU_DestroyAdvPopup();
   g_tcuAdvSetOpen = false;
   TCU_DestroyProfilesPopup();
   g_tcuProfileOpen = false;
   if(g_tcuCanvasCreated)
   {
      g_tcuCanvas.Destroy();
      g_tcuCanvasCreated = false;
   }
   ObjectDelete(0, TCUC_PFX + "CANVAS");
   ObjectsDeleteAll(0, TCUC_PFX);
   g_tcuCanvasW = 0;
   g_tcuCanvasH = 0;
}

void TCU_ResetVisibleEdits()
{
   g_tcuVisibleEditCount = 0;
   ArrayResize(g_tcuVisibleEdits, 0);
}

void TCU_RegisterEdit(string name)
{
   ArrayResize(g_tcuVisibleEdits, g_tcuVisibleEditCount + 1);
   g_tcuVisibleEdits[g_tcuVisibleEditCount] = name;
   g_tcuVisibleEditCount++;
}

bool TCU_IsVisibleEdit(string name)
{
   for(int i = 0; i < g_tcuVisibleEditCount; i++)
      if(g_tcuVisibleEdits[i] == name) return true;
   return false;
}

// [v6.01 FIX] Lag-after-time root cause: this used to PARK stale OBJ_EDIT
// widgets at (-5000,-5000) instead of deleting them. Result was that every
// settings tab the user ever visited left a permanent orphan widget on the
// chart, and every redraw frame walked ALL chart objects and re-wrote
// XDISTANCE/YDISTANCE on each orphan -- even though they never moved. After
// ~5 min of clicking through tabs + receiving signals (each signal redraws
// some panel surfaces), orphans accumulated to 50-100+, turning every click
// and every 500 ms timer into a ~200-call ObjectSetInteger storm. Per-frame
// work scaled with how many tabs the user had opened: classic accumulation
// lag.
//
// New behaviour: actually delete stale edits. They'll be re-created on the
// next redraw of the tab that owns them via the ObjectFind(...) < 0 branch
// in TCU_EditRow / TCU_EditBox / TCU_EditBoxLarge / TCU_AdjustRow /
// TCU_PslEditBox. The active edit (the one the user is currently typing
// in) is exempt -- yanking it mid-keystroke would lose input.
void TCU_HideStaleEdits()
{
   int total = ObjectsTotal(0, 0, -1);
   string pfx = TCUC_PFX + "ED_";
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, pfx) != 0) continue;
      if(TCU_IsVisibleEdit(name)) continue;
      // Don't yank the widget the user is typing into.
      if(g_tcuActiveEdit == name) continue;
      ObjectDelete(0, name);
   }
}

void TCU_DrawPill(int x, int y, int w, int h, string txt, color fill, color fg, int sz = 7)
{
   TCU_FillRoundRectAA(x, y, w, h, h / 2, TCU_A(fill));
   g_tcuCanvas.FontSet("Segoe UI Semibold", -(sz * 10));
   int tw = 0, th = 0;
   g_tcuCanvas.TextSize(txt, tw, th);
   g_tcuCanvas.TextOut(x + (w - tw) / 2, y + (h - th) / 2, txt, TCU_A(fg));
}

void TCU_Section(int x, int &y, string title)
{
   y += 10;
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 5, TCU_A(C'18,22,34'));
   TCU_TextBold(x + 8, y + 7, title, TCU_A(TCUC_ACC), 7);
   y += 30;
}

void TCU_Row(int x, int &y, string label, string value, color valueColor = clrWhite)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
   TCU_Text(x + 8, y + 7, label, TCU_A(TCUC_DIM), 7);
   TCU_TextBold(x + 150, y + 7, TCU_Short(value, 24), TCU_A(valueColor), 7);
   y += 27;
}

void TCU_CompactSection(int x, int &y, string title)
{
   y += 6;
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 22, 5, TCU_A(C'18,22,34'));
   TCU_TextBold(x + 8, y + 6, title, TCU_A(TCUC_ACC), 7);
   y += 26;
}

void TCU_CompactRow(int x, int &y, string label, string value, color valueColor = clrWhite)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 22, 4, TCU_A(TCUC_CARD));
   TCU_Text(x + 8, y + 6, label, TCU_A(TCUC_DIM), 7);
   TCU_TextBold(x + 150, y + 6, TCU_Short(value, 24), TCU_A(valueColor), 7);
   y += 24;
}

void TCU_ToggleRow(int x, int &y, string hit, string label, bool state)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
   TCU_Text(x + 8, y + 7, label, TCU_A(TCUC_DIM), 7);
   TCU_Btn(hit, x + TCUC_W - 92, y + 3, 66, 18, state ? "ON" : "OFF",
           TCU_A(state ? C'0,112,73' : C'96,32,50'), TCU_A(TCUC_TXT), 7, 4);
   y += 27;
}

void TCU_CycleRow(int x, int &y, string hit, string label, string value)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
   TCU_Text(x + 8, y + 7, label, TCU_A(TCUC_DIM), 7);
   TCU_Btn(hit, x + 150, y + 3, TCUC_W - 186, 18, TCU_Short(value, 20),
            TCU_A(C'31,52,82'), TCU_A(TCUC_ACC), 7, 4);
   y += 27;
}

void TCU_AdjustRow(int x, int &y, string key, string label, string value)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
   TCU_Text(x + 8, y + 7, label, TCU_A(TCUC_DIM), 7);
   int bx = x + 150;
   TCU_Btn("TCU_ADJ_DEC_" + key, bx, y + 3, 24, 18, "-", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 4);
   string name = TCUC_PFX + "ED_" + key;
   TCU_RegisterEdit(name);
   bool created = (ObjectFind(0, name) < 0);
   if(created)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      // [v6.01 FIX] one-time static props -- see TCU_EditRow comment for why.
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'31,52,82');
      ObjectSetInteger(0, name, OBJPROP_COLOR, TCUC_ACC);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, TCUC_GRID);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
   }
   TCU_PositionEdit(name, g_panelX + bx + 28, g_panelY + y + 3, 76, 18);
   TCU_SetEditText(name, value);
   TCU_Btn("TCU_ADJ_INC_" + key, bx + 108, y + 3, 24, 18, "+", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 4);
   y += 27;
}

// [v6.01 FIX] Reposition + text-update an existing OBJ_EDIT only when the
// values actually changed. Re-writing XDISTANCE/YDISTANCE every frame is
// what made the edit boxes invisible until clicked: MT5 reparents the
// underlying Win32 widget on every property write, leaving it in a
// "needs-paint-on-focus" state that the next canvas Update() then paints
// over. Skipping no-op writes restores the always-visible behaviour and
// also slashes per-frame ObjectSetInteger calls on the Source / Filter /
// Trade tabs (the rows full of inputs) which were the lag hot spot.
void TCU_PositionEdit(string name, int xWanted, int yWanted, int xSize, int ySize)
{
   long curX = ObjectGetInteger(0, name, OBJPROP_XDISTANCE);
   long curY = ObjectGetInteger(0, name, OBJPROP_YDISTANCE);
   if((int)curX != xWanted)
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xWanted);
   if((int)curY != yWanted)
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yWanted);
   long curXS = ObjectGetInteger(0, name, OBJPROP_XSIZE);
   long curYS = ObjectGetInteger(0, name, OBJPROP_YSIZE);
   if((int)curXS != xSize)
      ObjectSetInteger(0, name, OBJPROP_XSIZE, xSize);
   if((int)curYS != ySize)
      ObjectSetInteger(0, name, OBJPROP_YSIZE, ySize);
}

void TCU_SetEditText(string name, string value)
{
   if(g_tcuActiveEdit == name) return;  // user is typing, don't clobber
   string cur = ObjectGetString(0, name, OBJPROP_TEXT);
   if(cur != value)
      ObjectSetString(0, name, OBJPROP_TEXT, value);
}

void TCU_EditRow(int x, int &y, string key, string label, string value, int w = 174)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
   TCU_Text(x + 8, y + 7, label, TCU_A(TCUC_DIM), 7);

   string name = TCUC_PFX + "ED_" + key;
   TCU_RegisterEdit(name);
   bool created = (ObjectFind(0, name) < 0);
   if(created)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      // One-time: static appearance properties.
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'31,52,82');
      ObjectSetInteger(0, name, OBJPROP_COLOR, TCUC_ACC);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, TCUC_GRID);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
   }
   TCU_PositionEdit(name, g_panelX + x + 150, g_panelY + y + 3, w, 18);
   TCU_SetEditText(name, value);
   y += 27;
}

void TCU_EditBox(string key, int x, int y, int w, string value, color bg = C'31,52,82', color fg = C'0,217,181')
{
   string name = TCUC_PFX + "ED_" + key;
   TCU_RegisterEdit(name);
   bool created = (ObjectFind(0, name) < 0);
   if(created)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      // [v6.01 FIX] one-time static props -- see TCU_EditRow comment for why.
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, TCUC_GRID);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
   }
   TCU_PositionEdit(name, g_panelX + x, g_panelY + y, w, 18);
   TCU_SetEditText(name, value);
}

void TCU_EditBoxLarge(string key, int x, int y, int w, int h, string value)
{
   string name = TCUC_PFX + "ED_" + key;
   TCU_RegisterEdit(name);
   bool created = (ObjectFind(0, name) < 0);
   if(created)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      // [v6.01 FIX] one-time static props -- see TCU_EditRow comment for why.
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'31,52,82');
      ObjectSetInteger(0, name, OBJPROP_COLOR, TCUC_ACC);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, TCUC_GRID);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_LEFT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
   }
   TCU_PositionEdit(name, g_panelX + x, g_panelY + y, w, h);
   TCU_SetEditText(name, value);
}

void TCU_LongEditBlock(int x, int &y, string key, string title, string example, string value)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 72, 6, TCU_A(TCUC_CARD));
   TCU_TextBold(x + 8, y + 8, title, TCU_A(TCUC_TXT), 7);
   TCU_HintText(x + 8, y + 25, example);
   TCU_EditBoxLarge(key, x + 8, y + 43, TCUC_W - 40, 22, value);
   y += 78;
}

void TCU_CompactEditBlock(int x, int &y, string key, string title, string example, string value)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 58, 6, TCU_A(TCUC_CARD));
   TCU_TextBold(x + 8, y + 7, title, TCU_A(TCUC_TXT), 7);
   TCU_HintText(x + 8, y + 22, example);
   TCU_EditBoxLarge(key, x + 8, y + 36, TCUC_W - 40, 16, value);
   y += 64;
}

void TCU_FilterEditBlock(int x, int &y, string toggleHit, bool state, string key, string title, string example, string value)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 72, 6, TCU_A(TCUC_CARD));
   TCU_TextBold(x + 8, y + 8, title, TCU_A(TCUC_TXT), 7);
   TCU_Btn(toggleHit, x + TCUC_W - 92, y + 5, 66, 18, state ? "ON" : "OFF",
           TCU_A(state ? C'0,112,73' : C'96,32,50'), TCU_A(TCUC_TXT), 7, 4);
   TCU_HintText(x + 8, y + 25, example);
   TCU_EditBoxLarge(key, x + 8, y + 43, TCUC_W - 40, 22, value);
   y += 78;
}

void TCU_PartialGridRow(int &y, int level, double pips, double closeValue, bool active, string moveLabel, bool moveOn)
{
   int x = 14;
   int cLabel = 22, cPips = 72, cClose = 132, cMove = 194, cOn = 292;
   string n = IntegerToString(level);
   TCU_FillRoundRectAA(x, y, TCUC_W - 28, 22, 4, TCU_A(active ? TCUC_CARD : C'13,17,27'));
   TCU_TextBold(cLabel, y + 6, "TP" + n, TCU_A(active ? TCUC_TXT : TCUC_DIM), 7);
   TCU_EditBox("PTP" + n, cPips, y + 2, 46, DoubleToString(pips, 1));
   TCU_EditBox((PartialCloseMode == PARTIAL_FIXED_LOTS ? "PTP" + n + "LOTS" : "PTP" + n + "PCT"),
               cClose, y + 2, 46, DoubleToString(closeValue, PartialCloseMode == PARTIAL_FIXED_LOTS ? 2 : 1),
               PartialCloseMode == PARTIAL_FIXED_LOTS ? C'68,49,20' : C'31,52,82',
               PartialCloseMode == PARTIAL_FIXED_LOTS ? TCUC_WARN : TCUC_ACC);
   TCU_Btn("TCU_PART_MV_" + n, cMove, y + 2, 50, 18, moveLabel,
           TCU_A(moveOn ? TCUC_ACC : TCUC_GRID), TCU_A(moveOn ? clrWhite : TCUC_DIM), 7, 3);
   TCU_Btn("TCU_PART_ON_" + n, cOn, y + 2, 34, 18, "ON",
           TCU_A(active ? TCUC_OK : TCUC_GRID), TCU_A(active ? clrWhite : TCUC_DIM), 7, 4);
   y += 24;
}

double TCU_SignalTpAlloc(int level)
{
   string parts[];
   int n = StringSplit(LotDistribution, ',', parts);
   if(level >= 1 && level <= n)
      return MathMax(0.0, StringToDouble(parts[level - 1]));
   return (level <= MaxTPTargets ? 100.0 / MathMax(1, MaxTPTargets) : 0.0);
}

double TCU_SignalTpFixedLots(int level)
{
   string parts[];
   int n = StringSplit(SignalTpLotValues, ',', parts);
   if(level >= 1 && level <= n)
      return MathMax(0.0, StringToDouble(parts[level - 1]));
   return 0.0;
}

void TCU_SetSignalTpAlloc(int level, double value)
{
   double vals[3];
   for(int i = 0; i < 3; i++) vals[i] = TCU_SignalTpAlloc(i + 1);
   if(level >= 1 && level <= 3) vals[level - 1] = MathMax(0.0, value);
   LotDistribution = DoubleToString(vals[0], 0) + "," + DoubleToString(vals[1], 0) + "," +
                     DoubleToString(vals[2], 0);
}

void TCU_SetSignalTpFixedLot(int level, double value)
{
   double vals[3];
   for(int i = 0; i < 3; i++) vals[i] = TCU_SignalTpFixedLots(i + 1);
   if(level >= 1 && level <= 3) vals[level - 1] = MathMax(0.0, value);
   SignalTpLotValues = DoubleToString(vals[0], 2) + "," + DoubleToString(vals[1], 2) + "," +
                       DoubleToString(vals[2], 2);
}

bool TCU_BuildSignalTpLots(string sym, double totalLots, int &numTPs, double &lot1, double &lot2, double &lot3, string tag)
{
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN); if(minLot <= 0) minLot = 0.01;
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP); if(stepLot <= 0) stepLot = minLot;
   double brokerMaxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX); if(brokerMaxLot <= 0) brokerMaxLot = 1000.0;
   int affordableLegs = (int)MathFloor(totalLots / minLot);
   if(affordableLegs < 1) affordableLegs = 1;
   bool overrideMain = (SignalTpAllocMode == PARTIAL_FIXED_LOTS);
   if(!overrideMain)
   {
      if(numTPs > affordableLegs)
      {
         Print("[", tag, "] lotsTotal ", DoubleToString(totalLots, 2),
               " too small for ", numTPs, " legs at minLot ",
               DoubleToString(minLot, 2), " -- collapsing to ",
               affordableLegs, " leg(s).");
         numTPs = affordableLegs;
      }
      if(numTPs < 1) numTPs = 1;
   }

   double legs[3]; legs[0] = 0; legs[1] = 0; legs[2] = 0;
   bool useFixed = (SignalTpAllocMode == PARTIAL_FIXED_LOTS);

   if(useFixed)
   {
      double cfg[3];
      cfg[0] = TCU_SignalTpFixedLots(1);
      cfg[1] = TCU_SignalTpFixedLots(2);
      cfg[2] = TCU_SignalTpFixedLots(3);
      double sumCfg = 0;
      bool invalidCfg = false;
      for(int i = 0; i < numTPs; i++)
      {
         if(cfg[i] <= 0) invalidCfg = true;
         sumCfg += cfg[i];
      }
      if(invalidCfg || sumCfg <= 0)
      {
         Print("[", tag, "] Signal TP fixed-lot config invalid for active legs -- falling back to percentage split.");
         useFixed = false;
         if(overrideMain)
         {
            overrideMain = false;
            if(numTPs > affordableLegs)
            {
               Print("[", tag, "] Fallback to percent requires affordable-leg collapse to ", affordableLegs, ".");
               numTPs = affordableLegs;
            }
         }
      }
      else
      {
         if(overrideMain)
         {
            for(int i = 0; i < numTPs; i++)
            {
               double leg = MathFloor(cfg[i] / stepLot) * stepLot;
               if(leg < minLot) leg = minLot;
               if(SkipIfLotOverMax && leg > MaxLotSize)
               {
                  Print("[", tag, "] Signal TP fixed lot ", DoubleToString(leg, 2),
                        " exceeds MaxLotSize ", DoubleToString(MaxLotSize, 2),
                        " while SkipIfLotOverMax is ON.");
                  return false;
               }
               if(leg > MaxLotSize) leg = MaxLotSize;
               if(leg > brokerMaxLot) leg = brokerMaxLot;
               legs[i] = NormalizeDouble(leg, 2);
            }
         }
         else
         {
            double scale = totalLots / sumCfg;
            double usedLots = 0;
            for(int i = 0; i < numTPs - 1; i++)
            {
               double leg = MathFloor((cfg[i] * scale) / stepLot) * stepLot;
               if(leg < minLot) leg = minLot;
               legs[i] = NormalizeDouble(leg, 2);
               usedLots += legs[i];
            }
            double remaining = totalLots - usedLots;
            if(remaining < minLot) remaining = minLot;
            remaining = MathFloor(remaining / stepLot) * stepLot;
            if(remaining < minLot) remaining = minLot;
            legs[numTPs - 1] = NormalizeDouble(remaining, 2);
         }
      }
   }

   if(!useFixed)
   {
      double usedLots = 0;
      for(int i = 0; i < numTPs - 1; i++)
      {
         double p = TCU_SignalTpAlloc(i + 1);
         if(p <= 0) p = 100.0 / MathMax(1, numTPs);
         double leg = MathFloor((totalLots * (p / 100.0)) / stepLot) * stepLot;
         if(leg < minLot) leg = minLot;
         legs[i] = NormalizeDouble(leg, 2);
         usedLots += legs[i];
      }
      double remaining = totalLots - usedLots;
      if(remaining < minLot) remaining = minLot;
      remaining = MathFloor(remaining / stepLot) * stepLot;
      if(remaining < minLot) remaining = minLot;
      legs[numTPs - 1] = NormalizeDouble(remaining, 2);
   }

   lot1 = legs[0];
   lot2 = legs[1];
   lot3 = legs[2];
   return true;
}

void TCU_SignalTpGridRow(int &y, int level)
{
   int x = 14;
   int cLabel = 22, cAlloc = 118, cUse = 238, cOn = 292;
   bool active = (level <= MaxTPTargets);
   string n = IntegerToString(level);
   bool fixedLots = (SignalTpAllocMode == PARTIAL_FIXED_LOTS);
   string editKey = "SIGTP" + n + (fixedLots ? "LOT" : "PCT");
   double editVal = fixedLots ? TCU_SignalTpFixedLots(level) : TCU_SignalTpAlloc(level);
   TCU_FillRoundRectAA(x, y, TCUC_W - 28, 22, 4, TCU_A(active ? TCUC_CARD : C'13,17,27'));
   TCU_TextBold(cLabel, y + 6, "TP" + n, TCU_A(active ? TCUC_TXT : TCUC_DIM), 7);
   TCU_EditBox(editKey, cAlloc, y + 2, 54, DoubleToString(editVal, fixedLots ? 2 : 0),
               fixedLots ? C'68,49,20' : C'31,52,82',
               fixedLots ? TCUC_WARN : TCUC_ACC);
   TCU_Text(cAlloc + 60, y + 6, fixedLots ? "lots" : "% lots", TCU_A(TCUC_DIM), 7);
   TCU_Text(cUse, y + 6, level == 1 ? "Main TP" : "Split leg", TCU_A(TCUC_DIM), 7);
   TCU_Btn("TCU_SIGTP_ON_" + n, cOn, y + 2, 34, 18, "ON",
           TCU_A(active ? TCUC_OK : TCUC_GRID), TCU_A(active ? clrWhite : TCUC_DIM), 7, 4);
   y += 24;
}

void TCU_InfoRow(int x, int &y, string label, string value)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
   TCU_Text(x + 8, y + 7, label, TCU_A(TCUC_DIM), 7);
   TCU_TextBold(x + 150, y + 7, TCU_Short(value, 24), TCU_A(TCUC_TXT), 7);
   y += 27;
}

void TCU_NoteText(int x, int y, string text)
{
   TCU_Text(x, y, text, TCU_A(TCUC_NOTE), 7);
}

void TCU_HintText(int x, int y, string text)
{
   TCU_Text(x, y, text, TCU_A(TCUC_HINT), 7);
}

bool TCU_CompactTopSummary()
{
   return (g_tcuTab == 7 || g_tcuTab == 10 || g_tcuTab == 13);
}

int TCU_ContentY()
{
   return TCU_CompactTopSummary() ? TCUC_CONTENT_Y_COMPACT : TCUC_CONTENT_Y;
}

void TCU_DrawSettingsNav(int x, int &y)
{
   string cats[9] = {"Source", "Copier", "Lots", "Filter", "Trade", "Stops", "News", "Alerts", "System"};
   int w = 52;
   int h = 22;
   int gap = 6;
   int cx = x;
   for(int i = 0; i < 9; i++)
   {
      if(i == 5) { cx = x; y += h + gap; }
      bool active = (g_tcuSettingsCat == i);
      color shell = active ? TCUC_ACC : C'44,54,78';
      color fill  = active ? TCUC_ACC : C'19,24,36';
      TCU_FillRoundRectAA(cx, y, w, h, 4, TCU_A(shell));
      TCU_FillRoundRectAA(cx + 1, y + 1, w - 2, h - 2, 4, TCU_A(fill));
      g_tcuCanvas.FontSet("Segoe UI Semibold", -60);
      int tw = 0, th = 0;
      g_tcuCanvas.TextSize(cats[i], tw, th);
      g_tcuCanvas.TextOut(cx + (w - tw) / 2, y + (h - th) / 2, cats[i], TCU_A(active ? TCUC_TXT : C'164,173,193'));
      TCU_RegHit("TCU_SET_CAT_" + IntegerToString(i), cx, y, w, h);
      cx += w + gap;
   }
   y += h + 10;
}

void TCU_DrawHeader()
{
   TCU_FillRoundRectAA(0, 0, TCUC_W, TCUC_H, 10, TCU_A(TCUC_BRD));
   TCU_FillRoundRectAA(1, 1, TCUC_W - 2, TCUC_H - 2, 9, TCU_A(TCUC_BG));
   TCU_FillRoundRectAA(8, 8, TCUC_W - 16, 46, 8, TCU_A(TCUC_PNL));
   TCU_TextBold(16, 16, "TRADE COPIER ULTIMATE", TCU_A(TCUC_TXT), 9);
   TCU_Text(17, 33, "Navigator Algo", TCU_A(TCUC_DIM), 6);
   TCU_TextBold(198, 19, TCU_VERSION_STR, TCU_A(TCUC_DIM), 6);
   string statusTxt = TCU_StatusText();
   g_tcuCanvas.FontSet("Segoe UI Semibold", -70);
   int stw = 0, sth = 0;
   g_tcuCanvas.TextSize(statusTxt, stw, sth);
   int pillW = MathMax(60, stw + 24);
   int pillX = 352 - (pillW + 62 + 4 + 16 + 4 + 16);
   TCU_DrawPill(pillX, 14, pillW, 26, statusTxt, TCU_StatusColor(), clrWhite, 7);
   TCU_Btn("TCU_MONITOR", pillX + pillW + 4, 14, 62, 26, "ORDERS", TCU_A(g_tcuMonOpen ? TCUC_ACC : TCUC_GRID), TCU_A(TCUC_TXT), 7, 5);
   TCU_Btn("TCU_SETTINGS", pillX + pillW + 70, 14, 16, 26, "C", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 5);
   TCU_Btn("TCU_MIN", pillX + pillW + 90, 14, 16, 26, "-", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 9, 5);

   string tabs[15] = {"Home", "Source", "Copier", "Lots", "Filter", "Trade", "Auto SL/TP",
                      "SigTP", "Trail", "News", "Partial", "Alerts", "Prop", "Martin", "System"};
   int tabY = 60;
   TCU_FillRoundRectAA(8, tabY, TCUC_W - 16, 82, 6, TCU_A(TCUC_PNL));
   int gap = 6;
   int tabWidths[15] = {58, 64, 64, 54, 62, 58, 86, 58, 54, 54, 58, 60, 50, 54, 64};
   for(int i = 0; i < 15; i++)
   {
      int row = 0;
      int start = 0;
      int stop = 5;
      if(i >= 5 && i < 10) { row = 1; start = 5; stop = 10; }
      else if(i >= 10) { row = 2; start = 10; stop = 15; }
      int rowW = -gap;
      for(int j = start; j < stop; j++)
         rowW += tabWidths[j] + gap;
      int tx = 8 + (TCUC_W - 16 - rowW) / 2;
      for(int j = start; j < i; j++)
         tx += tabWidths[j] + gap;
      int tw = tabWidths[i];
      int ty = tabY + 3 + row * 26;
      int off = ("TCU_TAB_" + IntegerToString(i) == g_tcuPressed) ? 1 : 0;
      if(i == g_tcuTab)
      {
         TCU_FillRoundRectAA(tx, ty + off, tw, 22, 5, TCU_A(TCUC_ACC));
         TCU_FillRoundRectAA(tx + 1, ty + off + 1, tw - 2, 20, 5, TCU_A(TCUC_ACC));
         g_tcuCanvas.FontSet("Segoe UI Semibold", -80);
         int twText = 0, thText = 0;
         g_tcuCanvas.TextSize(tabs[i], twText, thText);
         g_tcuCanvas.TextOut(tx + (tw - twText) / 2, ty + off + (22 - thText) / 2, tabs[i], TCU_A(TCUC_TXT));
      }
      else
      {
         TCU_FillRoundRectAA(tx, ty + off, tw, 22, 5, TCU_A(C'42,50,72'));
         TCU_FillRoundRectAA(tx + 1, ty + off + 1, tw - 2, 20, 5, TCU_A(C'19,24,36'));
         g_tcuCanvas.FontSet("Segoe UI Semibold", -80);
         int twText = 0, thText = 0;
         g_tcuCanvas.TextSize(tabs[i], twText, thText);
         g_tcuCanvas.TextOut(tx + (tw - twText) / 2, ty + off + (22 - thText) / 2, tabs[i], TCU_A(C'164,173,193'));
      }
      // Hide Martin tab (index 13) unless both unlock inputs are set
      if(i == 13 && !g_showMartingaleTab)
      {
         TCU_FillRoundRectAA(tx, ty, tw, 22, 5, TCU_A(TCUC_PNL));
         continue;
      }
      TCU_RegHit("TCU_TAB_" + IntegerToString(i), tx, ty, tw, 22);
   }

   if(!TCU_CompactTopSummary())
   {
      TCU_FillRoundRectAA(8, 148, TCUC_W - 16, 46, 8, TCU_A(TCUC_PNL));
      TCU_FillRoundRectAA(14, 153, 108, 36, 8, TCU_A(TCUC_CARD));
      TCU_TextBold(40, 163, _Symbol, TCU_A(TCUC_TXT), 10);

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double spread = (point > 0) ? (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point : 0;
      color spreadColor = (EnableSpreadFilter && spread > MaxSpreadPoints) ? TCUC_DNG : (spread > 30 ? TCUC_WARN : TCUC_OK);
      TCU_Text(132, 159, "Spread: " + DoubleToString(spread, 1), TCU_A(spreadColor), 6);
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double pnl = eq - bal;
      TCU_TextBold(226, 155, "$" + DoubleToString(eq, 2), TCU_A(TCUC_TXT), 8);
      TCU_TextBold(226, 173, (pnl >= 0 ? "+" : "") + DoubleToString(pnl, 2), TCU_A(pnl >= 0 ? TCUC_OK : TCUC_DNG), 7);
      TCU_TextBold(286, 167, TCU_StatusText(), TCU_A(TCU_StatusColor()), 6);
   }
}

void TCU_DrawSignalsTab()
{
   int x = 12, y = TCU_ContentY();
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 22, 5, TCU_A(C'18,22,34'));
   TCU_TextBold(x + 8, y + 7, "SIGNAL INGESTION", TCU_A(TCUC_ACC), 7);
   TCU_Btn("TCU_TEST", x + 188, y + 3, 64, 18, "TEST", TCU_A(C'20,55,48'), TCU_A(TCUC_OK), 7, 4);
   TCU_Btn("TCU_ARM", x + 258, y + 3, 66, 18, ArmExecution ? "DISARM" : "ARM", TCU_A(ArmExecution ? C'85,34,49' : C'0,95,70'), TCU_A(TCUC_TXT), 7, 4);
   y += 28;
   TCU_CompactRow(x, y, "AutoTrading", TCU_AutoTradingStatusText(), TCU_AutoTradingAllowed() ? TCUC_OK : TCUC_DNG);
   TCU_CompactRow(x, y, "Bridge", TCU_BridgeStatus() + " :" + IntegerToString(BridgePort), EnableBridgeMode ? TCUC_OK : TCUC_DIM);
   TCU_CompactRow(x, y, "Telegram Bot", TCU_TelegramStatus(), EnableBotAPIMode ? TCUC_OK : TCUC_DIM);
      TCU_CompactRow(x, y, "Discord Send", TCU_OnOff(EnableDiscordMode), EnableDiscordMode ? TCUC_OK : TCUC_DIM);
   TCU_CompactRow(x, y, "Signals Parsed", IntegerToString(g_signalsProcessed), TCUC_TXT);
   TCU_CompactRow(x, y, "Last Signal", StringLen(g_lastSignal) > 0 ? g_lastSignal : "None", TCUC_TXT);
   TCU_CompactRow(x, y, "Filtered", StringLen(g_lastFilterReason) > 0 ? g_lastFilterReason : "None", StringLen(g_lastFilterReason) > 0 ? TCUC_WARN : TCUC_DIM);
   TCU_CompactSection(x, y, "LIVE STATUS");
   TCU_CompactRow(x, y, "Prop Mode", TCU_OnOff(PropFirmMode), PropFirmMode ? TCUC_WARN : TCUC_DIM);
   TCU_CompactRow(x, y, "Global Partials", TCU_OnOff(EnablePartialClose), EnablePartialClose ? TCUC_OK : TCUC_DIM);
   TCU_CompactRow(x, y, "Partials Scope", EnablePartialClose ? TCU_PartialScopeText() : "OFF", EnablePartialClose ? TCUC_ACC : TCUC_DIM);
   TCU_CompactRow(x, y, "Signal Multi-TP", TCU_OnOff(EnableMultiTP), EnableMultiTP ? TCUC_OK : TCUC_DIM);
   TCU_CompactRow(x, y, "Trailing Stop", TCU_OnOff(EnableTrailingStop), EnableTrailingStop ? TCUC_OK : TCUC_DIM);
   TCU_CompactRow(x, y, "News Pause", TCU_OnOff(EnableNewsPause), EnableNewsPause ? TCUC_WARN : TCUC_DIM);
}

void TCU_DrawCopierTab()
{
   int x = 12, y = TCU_ContentY();
   TCU_Section(x, y, "EA-TO-EA COPIER");
      TCU_Row(x, y, "Copier Mode", TCU_CopierModeText(), CopierMode == MODE_DISABLED ? TCUC_DIM : TCUC_OK);
   TCU_Row(x, y, "CSV File", CopierFileName, TCUC_TXT);
   TCU_Row(x, y, "Poll Speed", IntegerToString(CopierPollMs) + " ms", TCUC_ACC);
   TCU_Row(x, y, "Startup Copy", TCU_CopierStartupModeText(), CopierStartupCopyMode == COPY_NEW_TRADES_ONLY ? TCUC_OK : TCUC_WARN);
   TCU_ToggleRow(x, y, "TCU_COPIER_CLOSE", "Auto-close Slave", CopierAutoClose);
   TCU_Row(x, y, "Trades Received", IntegerToString(g_tradesReceived), TCUC_OK);
   TCU_Row(x, y, "Trades Sent", IntegerToString(g_tradesSent), TCUC_TXT);
   TCU_Section(x, y, "COPIER LOTS");
      TCU_Row(x, y, "Lot Mode", TCU_CopierLotModeText(), TCUC_ACC);
   TCU_Row(x, y, "Fixed / Mult", DoubleToString(CopierFixedLot, 2) + " / " + DoubleToString(CopierLotMultiplier, 2), TCUC_TXT);
   TCU_Row(x, y, "Risk / Max", DoubleToString(CopierRiskPercent, 2) + "% / " + DoubleToString(CopierMaxLot, 2), TCUC_TXT);
   TCU_Row(x, y, "Min Lot", DoubleToString(CopierMinimumLotToCopy, 2), TCUC_TXT);
   TCU_Row(x, y, "Comment", TCU_CopierTradeCommentModeText(), TCUC_TXT);
}

void TCU_DrawExecTab()
{
   int x = 12, y = TCUC_CONTENT_Y;
   TCU_Section(x, y, "LOT SIZING");
   TCU_Row(x, y, "Lot Mode", TCU_LotModeText(), TCUC_ACC);
   if(LotMode == LOT_RISK_PERCENT)
   {
      TCU_Row(x, y, "Risk %", DoubleToString(RiskPercent, 2), TCUC_TXT);
      TCU_Row(x, y, "Default SL pts", IntegerToString(DefaultSLPoints), TCUC_TXT);
   }
   else
      TCU_Row(x, y, "Fixed Lot", DoubleToString(FixedLotSize, 2), TCUC_TXT);
   TCU_Row(x, y, "Max Lot", DoubleToString(MaxLotSize, 2), TCUC_TXT);
   // [v6.00 NEW][PerSymUI] Per-Symbol Lots block: live preview + [Add] / [Configure] entry points.
   // Always parse main lots here regardless of MG popup state.
   { bool _m = g_tcuPslIsMGMode; g_tcuPslIsMGMode = false; Psl_ParseFromString(); g_tcuPslIsMGMode = _m; }
   TCU_Section(x, y, "PER-SYMBOL LOTS");
   // Add-row: text input + [Add] button. Symbol typed here is validated against MarketWatch
   // and inserted with default 0.01 lot (user adjusts in the Configure modal).
   {
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
      TCU_Text(x + 8, y + 7, "Add symbol", TCU_A(TCUC_DIM), 7);
      TCU_EditBox("PSLADD", x + 96, y + 3, 110, g_tcuPslAddInputCache);
      TCU_Btn("TCU_PSL_ADD", x + 210, y + 3, 50, 18, "Add", TCU_A(TCUC_ACC), TCU_A(clrWhite), 7, 4);
      string cfgLabel = "Configure (" + IntegerToString(g_pslCount) + ")";
      TCU_Btn("TCU_PSL_OPEN", x + 264, y + 3, TCUC_W - 24 - 264 - 4, 18, cfgLabel, TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 7, 4);
      y += 27;
   }
   // Transient feedback banner (cleared after ~5 s)
   if(StringLen(g_tcuPslAddBanner) > 0)
   {
      ulong now = GetTickCount64();
      if(now - g_tcuPslAddBannerAt > 5000) { g_tcuPslAddBanner = ""; }
      else
      {
         bool isErr = (StringFind(g_tcuPslAddBanner, "not in") >= 0
                    || StringFind(g_tcuPslAddBanner, "already")  >= 0
                    || StringFind(g_tcuPslAddBanner, "Max ")     >= 0
                    || StringFind(g_tcuPslAddBanner, "Type ")    >= 0);
         TCU_Row(x, y, "Status", g_tcuPslAddBanner, isErr ? TCUC_WARN : TCUC_OK);
      }
   }
   // Live preview of currently configured symbols. Reads parsed arrays so it always
   // matches what the modal will show.
   if(g_pslCount == 0)
   {
      TCU_Row(x, y, "Overrides", "none -- all symbols use Global Lot Mode", TCUC_DIM);
   }
   else
   {
      int psShown = 0;
      for(int psI = 0; psI < g_pslCount && psShown < 6; psI++, psShown++)
      {
         string keyLabel = g_pslKeys[psI];
         // [v6.00 NEW][PerSymUI] Use cached resolved name -- avoids per-frame MarketWatch walk.
         string keyResolved = (ArraySize(g_pslResolved) > psI) ? g_pslResolved[psI] : "";
         if(StringLen(keyResolved) > 0 && keyResolved != keyLabel) keyLabel = keyLabel + " (" + keyResolved + ")";
         color rowClr = (StringLen(keyResolved) > 0) ? TCUC_OK : TCUC_DNG;
         TCU_Row(x, y, keyLabel, DoubleToString(g_pslLots[psI], 2), rowClr);
      }
      if(g_pslCount > 6)
         TCU_Row(x, y, "+" + IntegerToString(g_pslCount - 6) + " more", "open Configure to view", TCUC_DIM);
      int slotsLeft = TCU_PERSYMBOL_MAX - g_pslCount;
      TCU_Row(x, y, "Slots left", IntegerToString(slotsLeft) + " / " + IntegerToString(TCU_PERSYMBOL_MAX), TCUC_DIM);
   }
   TCU_HintText(x + 4, y + 4, "Symbols not listed use Global Lot Mode (" + TCU_LotModeText() + ").");
   y += 12;
   TCU_Section(x, y, "EXECUTION RULES");
   TCU_ToggleRow(x, y, "TCU_REVERSE", "Reverse Signal", ReverseSignal);
   TCU_ToggleRow(x, y, "TCU_COPYSL", "Copy SL", CopySL);
   TCU_ToggleRow(x, y, "TCU_COPYTP", "Copy TP", CopyTP);
   TCU_Row(x, y, "Slippage Action", EnumToString(SlippageAction), TCUC_TXT);
}

void TCU_DrawProtectTab()
{
   int x = 12, y = TCUC_CONTENT_Y;
   TCU_Section(x, y, "CIRCUIT BREAKERS");
   TCU_Row(x, y, "Max Trades/min", IntegerToString(MaxTradesPerMinute), TCUC_TXT);
   TCU_Row(x, y, "Max Open Pos", IntegerToString(MaxOpenPositions), TCUC_TXT);
   TCU_Row(x, y, "Daily Loss %", DoubleToString(MaxDailyLossPercent, 2), TCUC_WARN);
   TCU_ToggleRow(x, y, "TCU_PROP", "Prop Firm Mode", PropFirmMode);
   TCU_Section(x, y, "FILTERS");
   TCU_ToggleRow(x, y, "TCU_DUP", "Duplicate Filter", EnableDuplicateFilter);
   TCU_ToggleRow(x, y, "TCU_SPREAD", "Spread Filter", EnableSpreadFilter);
   TCU_Row(x, y, "Cooldown", IntegerToString(SignalCooldownSeconds) + " sec", TCUC_TXT);
}

void TCU_DrawManageTab()
{
   int x = 12, y = TCU_ContentY();
   TCU_Section(x, y, "POSITION MANAGEMENT");
   TCU_ToggleRow(x, y, "TCU_TRAIL", "Trailing Stop", EnableTrailingStop);
   TCU_ToggleRow(x, y, "TCU_PARTIAL", "Partial Close", EnablePartialClose);
   TCU_ToggleRow(x, y, "TCU_MULTITP", "Multi-TP", EnableMultiTP);
   TCU_Row(x, y, "Tracked Partials", IntegerToString(g_partialCount), TCUC_TXT);
   TCU_Row(x, y, "Multi-TP Legs", IntegerToString(g_mtpCount), TCUC_TXT);
   TCU_Section(x, y, "PENDING ORDERS");
   TCU_ToggleRow(x, y, "TCU_PENDING", "Pending Orders", EnablePendingOrders);
   TCU_ToggleRow(x, y, "TCU_PEXP", "Pending Expiry", EnablePendingExpiry);
   TCU_ToggleRow(x, y, "TCU_MODSTACK", "Update SL/TP in Cooldown", AllowSLTPModDuringCooldown);
}

string MG_ModeHintText()
{
   switch(MartingaleMode)
   {
      case 0: return "Classic: doubles lot size after each loss (x2^streak).";
      case 1: return "Custom: multiplies lot by your set factor after each loss.";
      case 2: return "Anti-Martin: increases lot on wins, decreases on losses.";
      case 3: return "Fixed Step: adds a fixed lot amount after each loss.";
   }
   return "";
}

void TCU_MG_ValueRow(int x, int &y, string label, string keyDec, string keyInc, string valStr)
{
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
   TCU_Text(x + 8, y + 7, label, TCU_A(TCUC_DIM), 7);
   int bx = x + 150;
   TCU_Btn(keyDec, bx, y + 3, 22, 18, "-", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 9, 3);
   string editKey = StringSubstr(keyDec, 12); // strip "TCU_ADJ_DEC_" -> base key
   string name = TCUC_PFX + "ED_" + editKey;
   TCU_RegisterEdit(name);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      C'31,52,82');
      ObjectSetInteger(0, name, OBJPROP_COLOR,        TCUC_ACC);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, TCUC_GRID);
      ObjectSetInteger(0, name, OBJPROP_ALIGN,        ALIGN_CENTER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     7);
      ObjectSetString(0,  name, OBJPROP_FONT,         "Segoe UI Semibold");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,       false);
      ObjectSetInteger(0, name, OBJPROP_BACK,         false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER,       20);
   }
   TCU_PositionEdit(name, g_panelX + bx + 26, g_panelY + y + 3, 72, 18);
   TCU_SetEditText(name, valStr);
   TCU_Btn(keyInc, bx + 102, y + 3, 22, 18, "+", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 9, 3);
   y += 27;
}

void TCU_DrawMartingaleTab()
{
   int x = 12, y = TCU_ContentY();

   // -- DISCLAIMER OVERLAY (must accept before using) --
   if(!g_mgDisclaimerAccepted)
   {
      // Border highlight (drawn as slightly larger background)
      TCU_FillRoundRectAA(x - 1, y - 1, TCUC_W - 22, 282, 9, TCU_A(C'180,60,60'));
      // Dark overlay background (inner fill)
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 280, 8, TCU_A(C'18,18,24'));

      // Experimental badge
      int bw = 160; int bx = x + (TCUC_W - 24) / 2 - bw / 2;
      TCU_FillRoundRectAA(bx, y + 8, bw, 18, 4, TCU_A(C'80,45,0'));
      TCU_TextBold(bx + bw/2 - 62, y + 12, "⚠  EXPERIMENTAL FEATURE", TCU_A(C'255,180,0'), 7);

      // Warning icon + title
      TCU_TextBold(x + (TCUC_W - 24) / 2 - 70, y + 34, "! RISK WARNING", TCU_A(TCUC_DNG), 12);

      // Disclaimer text
      int ty = y + 68;
      TCU_Text(x + 16, ty,      "Martingale and Advanced modes carry",    TCU_A(TCUC_TXT), 8); ty += 18;
      TCU_Text(x + 16, ty,      "SIGNIFICANT RISK of account loss.",      TCU_A(TCUC_WARN), 8); ty += 24;
      TCU_Text(x + 16, ty,      "This is an experimental feature.",       TCU_A(C'255,180,0'), 7); ty += 16;
      TCU_Text(x + 16, ty,      "Losses can exceed your initial deposit.", TCU_A(TCUC_TXT), 7); ty += 16;
      TCU_Text(x + 16, ty,      "These features multiply your lot sizes", TCU_A(TCUC_TXT), 7); ty += 16;
      TCU_Text(x + 16, ty,      "after losses which compounds risk.",     TCU_A(TCUC_TXT), 7); ty += 24;
      TCU_TextBold(x + 16, ty,  "We are NOT responsible for any losses",  TCU_A(TCUC_DNG), 7); ty += 16;
      TCU_TextBold(x + 16, ty,  "caused by your trading decisions.",      TCU_A(TCUC_DNG), 7); ty += 28;
      TCU_Text(x + 16, ty,      "By clicking below you accept full",     TCU_A(TCUC_DIM), 7); ty += 16;
      TCU_Text(x + 16, ty,      "responsibility for any outcomes.",       TCU_A(TCUC_DIM), 7);

      // I AGREE button
      TCU_Btn("TCU_MG_AGREE", x + (TCUC_W - 24) / 2 - 80, y + 235, 160, 32,
              "I UNDERSTAND & AGREE",
              TCU_A(C'130,40,40'), TCU_A(TCUC_TXT), 8, 6);
      return;
   }

   // -- MASTER TOGGLE --
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 34, 6,
      EnableMartingale ? TCU_A(C'20,55,48') : TCU_A(C'45,22,30'));
   TCU_TextBold(x + 10, y + 10,
      EnableMartingale ? "MARTINGALE  ON" : "MARTINGALE  OFF",
      TCU_A(EnableMartingale ? TCUC_OK : TCUC_DNG), 8);
   TCU_Btn("TCU_MG_TOGGLE", x + 140, y + 7, 66, 20,
      EnableMartingale ? "DISABLE" : "ENABLE",
      TCU_A(EnableMartingale ? C'85,34,49' : C'0,95,70'), TCU_A(TCUC_TXT), 7, 4);
   TCU_Btn("TCU_MG_HELP", x + TCUC_W - 162, y + 7, 66, 20, "? GUIDE",
      TCU_A(g_mgHelpOpen ? TCUC_ACC : C'35,45,65'), TCU_A(TCUC_TXT), 7, 3);
   TCU_Btn("TCU_MG_MONITOR", x + TCUC_W - 92, y + 7, 68, 20, "MONITOR",
      TCU_A(g_mgmOpen ? TCUC_ACC : C'28,42,60'), TCU_A(g_mgmOpen ? TCUC_TXT : TCUC_DIM), 7, 3);
   y += 40;

   // -- HOW TO USE OVERLAY (MULTI-PAGE) --
   if(g_mgHelpOpen)
   {
      int hH = TCUC_H - 44 - y;
      int ow = TCUC_W - 24;
      color headerClr = (g_mgHelpPage==0)?C'130,45,25':(g_mgHelpPage==1)?C'105,75,15':(g_mgHelpPage==2)?C'20,90,55':(g_mgHelpPage==3)?C'25,65,145':C'15,65,125';
      string pageTitle = (g_mgHelpPage==0)?"CLASSIC MARTINGALE":(g_mgHelpPage==1)?"CUSTOM MULTIPLIER":(g_mgHelpPage==2)?"ANTI-MARTINGALE":(g_mgHelpPage==3)?"FIXED STEP":"ADVANCED MODE";

      TCU_FillRoundRectAA(x, y, ow, hH, 6, TCU_A(C'10,15,28'));
      TCU_FillRoundRectAA(x, y, ow, 30, 6, TCU_A(headerClr));
      TCU_TextBold(x + 10, y + 9, pageTitle, TCU_A(clrWhite), 8);
      TCU_Btn("TCU_MG_HELP", x + ow - 44, y + 6, 38, 18, "X CLOSE", TCU_A(C'40,14,14'), TCU_A(clrWhite), 7, 3);

      int navY = y + hH - 28;
      TCU_FillRoundRectAA(x, navY, ow, 28, 6, TCU_A(C'16,22,38'));
      bool hasPrev = (g_mgHelpPage > 0);
      bool hasNext = (g_mgHelpPage < 4);
      TCU_Btn("TCU_MG_HELP_PREV", x + 6,       navY+4, 30, 20, "<", TCU_A(hasPrev?C'35,55,100':C'20,26,42'), TCU_A(hasPrev?clrWhite:TCUC_GRID), 10, 4);
      TCU_Btn("TCU_MG_HELP_NEXT", x + ow - 36, navY+4, 30, 20, ">", TCU_A(hasNext?C'35,55,100':C'20,26,42'), TCU_A(hasNext?clrWhite:TCUC_GRID), 10, 4);
      for(int pi=0; pi<5; pi++)
         TCU_FillRoundRectAA(x+(ow/2)-22+pi*11, navY+11, 7, 7, 3, TCU_A(pi==g_mgHelpPage?clrWhite:C'45,60,85'));

      int ty = y + 36;
      int cx = x + 10;
      int cw = ow - 20;

      if(g_mgHelpPage == 0)
      {
         TCU_TextBold(cx, ty, "Doubles lot size after every loss.", TCU_A(clrWhite), 8); ty+=18;
         TCU_Text(cx, ty, "One of the oldest strategies. Assumes a win will", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "eventually come and recover all previous losses.", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'20,30,50'));
         TCU_Text(cx+6, ty+4, "0.10 -> loss -> 0.20 -> loss -> 0.40 -> WIN -> reset", TCU_A(TCUC_DIM), 7); ty+=24;
         TCU_TextBold(cx, ty, "Key Settings:", TCU_A(TCUC_ACC), 7); ty+=14;
         TCU_Text(cx, ty, "Max Steps  -- max losses before auto-reset (keep 3-5)", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "Reset on Win  -- clears streak after any winning trade", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'48,20,8'));
         TCU_Text(cx+6, ty+4, "! Lot doubles every step. Max Steps is your safety net.", TCU_A(TCUC_WARN), 7);
      }
      else if(g_mgHelpPage == 1)
      {
         TCU_TextBold(cx, ty, "Multiplies lot by your chosen factor each loss.", TCU_A(clrWhite), 8); ty+=18;
         TCU_Text(cx, ty, "Softer than Classic. You control how fast the lot", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "grows. 1.5x is half as aggressive as Classic 2x.", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'20,30,50'));
         TCU_Text(cx+6, ty+4, "1.5x: 0.10 -> 0.15 -> 0.23 -> 0.34 -> WIN -> reset", TCU_A(TCUC_DIM), 7); ty+=24;
         TCU_TextBold(cx, ty, "Key Settings:", TCU_A(TCUC_ACC), 7); ty+=14;
         TCU_Text(cx, ty, "Multiplier  -- recommended range 1.3 to 2.0", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "Max Steps  -- keep to 4-6 for safe exposure", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'14,34,18'));
         TCU_Text(cx+6, ty+4, "Tip: Multiplier 1.0 = no scaling. Min useful = 1.1.", TCU_A(TCUC_OK), 7);
      }
      else if(g_mgHelpPage == 2)
      {
         TCU_TextBold(cx, ty, "Increases lot after WIN, resets after LOSS.", TCU_A(clrWhite), 8); ty+=18;
         TCU_Text(cx, ty, "Opposite of Classic. Ride winning streaks and cut", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "exposure when you lose. Profits fuel the next trade.", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'20,30,50'));
         TCU_Text(cx+6, ty+4, "2x: 0.10 -> WIN -> 0.20 -> WIN -> 0.40 -> LOSS -> reset", TCU_A(TCUC_DIM), 7); ty+=24;
         TCU_TextBold(cx, ty, "Key Settings:", TCU_A(TCUC_ACC), 7); ty+=14;
         TCU_Text(cx, ty, "Multiplier  -- how fast lot grows per win", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "Max Steps  -- caps how high lot goes on a streak", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'14,34,18'));
         TCU_Text(cx+6, ty+4, "Best for: trending markets with consistent wins.", TCU_A(TCUC_OK), 7);
      }
      else if(g_mgHelpPage == 3)
      {
         TCU_TextBold(cx, ty, "Adds a fixed lot amount after each loss.", TCU_A(clrWhite), 8); ty+=18;
         TCU_Text(cx, ty, "Most predictable mode. Growth is linear, not", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "exponential. Easy to calculate max exposure.", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'20,30,50'));
         TCU_Text(cx+6, ty+4, "Step 0.05: 0.10 -> 0.15 -> 0.20 -> 0.25 -> WIN -> reset", TCU_A(TCUC_DIM), 7); ty+=24;
         TCU_TextBold(cx, ty, "Key Settings:", TCU_A(TCUC_ACC), 7); ty+=14;
         TCU_Text(cx, ty, "Fixed Step  -- lot added per loss (e.g. 0.01, 0.05)", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "Max Steps  -- auto-reset after N consecutive losses", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'14,34,18'));
         TCU_Text(cx+6, ty+4, "Lowest risk of the 4 modes. Good for beginners.", TCU_A(TCUC_OK), 7);
      }
      else
      {
         TCU_TextBold(cx, ty, "Sizes lot to recover ALL losses + profit in one win.", TCU_A(clrWhite), 8); ty+=18;
         TCU_Text(cx, ty, "Uses trade TP to calculate the exact lot needed.", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "TP hit = carry cleared + one normal base-lot TP profit banked.", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'20,30,50'));
         TCU_Text(cx+6, ty+4, "lots = (Carry Loss + Base-Lot TP Profit) / (TP pips x pip value)", TCU_A(TCUC_DIM), 7); ty+=24;
         TCU_TextBold(cx, ty, "Key Settings:", TCU_A(TCUC_ACC), 7); ty+=14;
         TCU_Text(cx, ty, "Base Lot  -- defines the normal TP profit kept after recovery", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "Max Risk Cap  -- safety $ limit (0 = MaxLot only)", TCU_A(TCUC_TXT), 7); ty+=13;
         TCU_Text(cx, ty, "No signal TP? Set Auto TP pips in the Trade tab.", TCU_A(TCUC_TXT), 7); ty+=18;
         TCU_FillRoundRectAA(cx, ty, cw, 18, 4, TCU_A(C'48,20,8'));
         TCU_Text(cx+6, ty+4, "! Needs TP on signal OR Auto TP pips in Trade tab.", TCU_A(TCUC_WARN), 7);
      }
      return;
   }

   // Warning banner moved before sub-tabs to prevent bottom overflow
   if(EnableMartingale)
   {
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 26, 5, TCU_A(C'60,35,10'));
      TCU_TextBold(x + 8, y + 6, "! Set Max Daily Loss % before using Martingale.",
                   TCU_A(TCUC_WARN), 7);
      y += 32;
   }

   // -- SUB-TABS (navigation only -- tabs do NOT change active mode) --
   int subW = (TCUC_W - 24) / 2;
   bool isRec   = (MartingaleMode == 4);    // ACTIVE mode is Recovery
   bool viewRec = (g_mgViewTab == 1);       // currently VIEWING Recovery panel
   TCU_Btn("TCU_MGTAB_STRAT", x, y, subW, 26, "STRATEGIES",
      TCU_A(viewRec ? C'18,22,34' : TCUC_ACC), TCU_A(viewRec ? TCUC_DIM : TCUC_TXT), 8, 5);
   TCU_Btn("TCU_MGTAB_REC", x + subW, y, subW, 26, "ADVANCED",
      TCU_A(viewRec ? TCUC_ACC : C'18,22,34'), TCU_A(viewRec ? TCUC_TXT : TCUC_DIM), 8, 5);
   y += 32;

   // -- ACTIVE MODE INDICATOR + ACTIVATE BUTTON --
   if(!viewRec && isRec)
   {
      // Viewing Strategies but Recovery is active -- show warning + activate button
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 26, 4, TCU_A(C'50,30,10'));
      TCU_TextBold(x + 8, y + 7, "Advanced mode is active  --  strategies are OFF", TCU_A(TCUC_WARN), 7);
      y += 30;
      TCU_Btn("TCU_MG_ACTIVATE_STRAT", x, y, TCUC_W - 24, 24, "ACTIVATE SELECTED STRATEGY INSTEAD",
              TCU_A(C'42,72,42'), TCU_A(TCUC_TXT), 7, 4);
      y += 28;
   }
   else if(viewRec && !isRec)
   {
      // Viewing Recovery but a Strategy is active -- show which strategy is active + activate button
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 26, 4, TCU_A(C'20,40,60'));
      TCU_TextBold(x + 8, y + 7, "Active mode: " + MG_ModeText() + "  --  Advanced is OFF", TCU_A(TCUC_ACC), 7);
      y += 30;
      TCU_Btn("TCU_MG_ACTIVATE_REC", x, y, TCUC_W - 24, 24, "ACTIVATE ADVANCED MODE",
              TCU_A(C'0,72,90'), TCU_A(TCUC_TXT), 7, 4);
      y += 28;
   }
   else
   {
      // Viewing the panel that IS already active -- just show a small active badge
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 20, 4, TCU_A(C'12,40,28'));
      string badge = isRec ? "ADVANCED MODE ACTIVE" : (MG_ModeText() + " ACTIVE");
      TCU_TextBold(x + 8, y + 5, "● " + badge, TCU_A(TCUC_OK), 7);
      y += 24;
   }
   y += 4;

   int maxY = TCUC_H - 10;

   if(!viewRec)
   {
      // -- MODE SELECTOR --
      TCU_Section(x, y, "MODE");
      TCU_MG_ValueRow(x, y, "Base Lot", "TCU_ADJ_DEC_MG_BASELOT", "TCU_ADJ_INC_MG_BASELOT",
                      DoubleToString(MartingaleBaseLot, 2));
      TCU_NoteText(x + 8, y + 2, "Fixed base lot for this series. EA lot settings are ignored.");
      y += 16;
      {
         bool mgPslActive = (g_tcuPslOpen && g_tcuPslIsMGMode);
         int mgPslCnt = 0;
         if(StringLen(MGPerSymbolLots) > 0) { string _t[]; mgPslCnt = StringSplit(MGPerSymbolLots, ',', _t); }
         string mgBtnLbl = (mgPslCnt > 0) ? "Per-Sym Lots (" + IntegerToString(mgPslCnt) + ")" : "Per-Sym Lots";
         TCU_Btn("TCU_MG_PERSYM_OPEN", x, y, TCUC_W - 24, 22, mgBtnLbl,
                 TCU_A(mgPslActive ? TCUC_ACC : C'28,42,60'), TCU_A(mgPslActive ? TCUC_TXT : TCUC_DIM), 7, 4);
         y += 26;
      }
      TCU_CycleRow(x, y, "TCU_MG_MODE", "Strategy", MG_ModeText());
      string modeHint = MG_ModeHintText();
      if(StringLen(modeHint) > 0) { TCU_NoteText(x + 8, y + 2, modeHint); y += 16; }

      if(MartingaleMode == 1 || MartingaleMode == 2) // Custom or Anti
         TCU_MG_ValueRow(x, y, "Multiplier (x per loss)", "TCU_ADJ_DEC_MG_MULT", "TCU_ADJ_INC_MG_MULT",
                         DoubleToString(MartingaleMultiplier, 2));
      else if(MartingaleMode == 3) // Fixed step
         TCU_MG_ValueRow(x, y, "Step lots added per loss", "TCU_ADJ_DEC_MG_STEP", "TCU_ADJ_INC_MG_STEP",
                         DoubleToString(MartingaleFixedStep, 2));
   }
   else
   {
      // -- RECOVERY SETTINGS (viewRec panel) --
      TCU_Section(x, y, "ADVANCED MODE");
      int _advBw = (TCUC_W - 30) / 2;
      TCU_Btn("TCU_ADV_SET_OPEN",  x,              y, _advBw, 28, "SETTINGS",  TCU_A(C'22,38,62'),  TCU_A(TCUC_TXT), 8, 5);
      TCU_Btn("TCU_ADV_RESET_ALL", x + _advBw + 6, y, _advBw, 28, "RESET ALL", TCU_A(C'80,20,20'),  TCU_A(TCUC_TXT), 8, 5);
      y += 32;

      if(FallbackTPPips <= 0)
      {
         TCU_FillRoundRectAA(x, y, TCUC_W - 24, 40, 5, TCU_A(C'80,44,0'));
         TCU_TextBold(x + 8, y + 8, "! No Auto TP set", TCU_A(C'255,180,0'), 8);
         TCU_Text(x + 8, y + 24, "Signals without TP will use BASE LOT, not recovery sizing.", TCU_A(C'220,160,80'), 7);
         y += 44;
      }

      // -- LIVE RECOVERY MONITOR --
      if(y + 40 <= maxY)
      {
         TCU_Section(x, y, "LIVE RECOVERY MONITOR");
         bool _anyActive = false;
         for(int _ri = 0; _ri < g_mgCount && y + 30 <= maxY; _ri++)
         {
            double _cy = g_mgTable[_ri].carry;
            if(_cy <= 0) continue;
            _anyActive = true;
            bool _maxHit = (MartingaleMaxLoss > 0 && MathAbs(g_mgTable[_ri].mgPnl) >= MartingaleMaxLoss);

            TCU_FillRoundRectAA(x, y, TCUC_W - 24, 28, 5, TCU_A(C'18,22,34'));
            TCU_TextBold(x + 8,  y + 8, TCU_Short(g_mgTable[_ri].sym, 10), TCU_A(TCUC_TXT), 7);
            TCU_Text(x + 96, y + 4, "Carry to recover", TCU_A(TCUC_DIM), 6);
            if(_maxHit)
               TCU_TextBold(x + 96, y + 14, "$" + DoubleToString(_cy, 2) + "  (cap hit)", TCU_A(C'255,180,0'), 7);
            else
               TCU_TextBold(x + 96, y + 14, "$" + DoubleToString(_cy, 2), TCU_A(C'255,180,0'), 7);
            y += 31;
         }
         if(!_anyActive && y + 24 <= maxY)
         {
            TCU_FillRoundRectAA(x, y, TCUC_W - 24, 22, 5, TCU_A(C'18,22,34'));
            TCU_Text(x + 8, y + 6, "No active recovery  --  no open carry", TCU_A(TCUC_DIM), 7);
            y += 25;
         }
      }
   }

   // -- LIVE STATUS (Strategies mode only, when space allows) --
   if(!isRec && y + 58 <= maxY)
   {
      TCU_Section(x, y, "LIVE STATUS");
      int _mgActiveCount = 0;
      for(int _c = 0; _c < g_mgCount; _c++)
         if(g_mgTable[_c].streak != 0 || g_mgTable[_c].mgPnl != 0) _mgActiveCount++;

      if(_mgActiveCount == 0)
      {
         if(y + 26 <= maxY)
            TCU_Row(x, y, "No data yet", "Waiting for closed trades", TCUC_DIM);
      }
      else
      {
         int _shown = 0;
         for(int i = 0; i < g_mgCount && _shown < 6 && y + 26 <= maxY; i++)
         {
            int streak = g_mgTable[i].streak;
            double pnl  = g_mgTable[i].mgPnl;
            if(streak == 0 && pnl == 0) continue;
            _shown++;
            string multStr = "";
            if(EnableMartingale && streak > 0)
            {
               switch(MartingaleMode)
               {
                  case 0: multStr = "x" + DoubleToString(MathPow(2.0, streak), 1); break;
                  case 1: multStr = "x" + DoubleToString(MathPow(MartingaleMultiplier, streak), 2); break;
                  case 2: multStr = "x" + DoubleToString(MathPow(MartingaleMultiplier, streak), 2); break;
                  case 3: multStr = "+" + DoubleToString(MartingaleFixedStep * streak, 2) + "L"; break;
                  case 4: multStr = "R:$" + DoubleToString(MathAbs(pnl), 0); break;
               }
            }
            else multStr = "base";
            bool nearMax = (streak >= MartingaleMaxSteps - 1 && streak > 0);
            color rowClr = nearMax ? TCUC_DNG : (streak > 0 ? TCUC_WARN : TCUC_OK);
            string pnlStr = (pnl >= 0 ? "+" : "") + DoubleToString(pnl, 2);
            string val = "S:" + IntegerToString(streak) + "  " + multStr + "  P:" + pnlStr;
            TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
            TCU_Text(x + 8, y + 7, TCU_Short(g_mgTable[i].sym, 10), TCU_A(TCUC_DIM), 7);
            TCU_TextBold(x + 100, y + 7, val, TCU_A(rowClr), 7);
            TCU_Btn("TCU_MG_RST_" + IntegerToString(i), x + TCUC_W - 66, y + 3, 42, 18,
                    "RESET", TCU_A(C'42,50,72'), TCU_A(TCUC_DIM), 6, 4);
            y += 27;
         }
      }
   }

   // -- RESET ALL BUTTON --
   if(!isRec && y + 30 <= maxY)
   {
      y += 4;
      TCU_Btn("TCU_MG_RESETALL", x, y, TCUC_W - 24, 26, "RESET ALL STREAKS",
              TCU_A(C'42,50,72'), TCU_A(TCUC_TXT), 7, 5);
   }
}

void TCU_DrawNewsTab()
{
   int x = 12, y = TCU_ContentY();
   TCU_Section(x, y, "NEWS PAUSE ENGINE");
   bool active = IsNewsPauseActive(_Symbol, false);
   TCU_FillRoundRectAA(x, y, TCUC_W - 24, 86, 8, TCU_A(TCUC_CARD));
   TCU_TextBold(x + 12, y + 12, active ? "NEWS LOCK ACTIVE" : "Calendar pause monitor", TCU_A(active ? TCUC_WARN : TCUC_TXT), 8);
   TCU_Text(x + 12, y + 34, "Window: -" + IntegerToString(NewsPauseBeforeMinutes) + "m / +" +
            IntegerToString(NewsPauseAfterMinutes) + "m", TCU_A(TCUC_DIM), 7);
   TCU_Text(x + 12, y + 51, active ? TCU_Short(g_tcuNewsLockReason, 42) :
            "Loaded events: " + IntegerToString(g_tcuNewsCount), TCU_A(active ? TCUC_WARN : TCUC_DIM), 7);
   TCU_DrawPill(x + 220, y + 12, 88, 24, EnableNewsPause ? "ARMED" : "OFF",
                EnableNewsPause ? TCUC_OK : TCUC_GRID, clrWhite, 7);
   y += 98;
   TCU_Btn("TCU_NEWS_RELOAD", x, y, 102, 28, "Reload", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 7, 5);
   TCU_Btn("TCU_NEWS_TOGGLE", x + 112, y, 102, 28, EnableNewsPause ? "PAUSE ON" : "PAUSE OFF",
           TCU_A(EnableNewsPause ? C'0,95,70' : C'92,38,52'), TCU_A(TCUC_TXT), 7, 5);
   TCU_Btn("TCU_NEWS_LOAD", x + 224, y, 102, 28, "LOAD", TCU_A(C'31,52,82'), TCU_A(TCUC_TXT), 7, 5);
   y += 38;
   TCU_Section(x, y, "UPCOMING EVENTS");
   int shown = 0;
   datetime now = TimeCurrent();
   for(int i = 0; i < g_tcuNewsCount && shown < 6; i++)
   {
      if(g_tcuNews[i].time < now - 3600) continue;
      string stars = (g_tcuNews[i].impact >= 3) ? "***" : "**";
      TCU_Row(x, y, TimeToString(g_tcuNews[i].time, TIME_MINUTES) + "  " + g_tcuNews[i].currency,
              stars + " " + TCU_Short(g_tcuNews[i].name, 18), g_tcuNews[i].impact >= 3 ? TCUC_DNG : TCUC_WARN);
      shown++;
   }
   if(shown == 0)
      TCU_Row(x, y, "No events loaded", "Press LOAD", TCUC_DIM);
}

void TCU_DrawSystemTab()
{
   int x = 12, y = TCU_ContentY();
   int cat = (g_tcuTab >= 1) ? g_tcuTab - 1 : g_tcuSettingsCat;

   if(cat == 0)
   {
      TCU_Section(x, y, "SIGNAL SOURCES");
      TCU_ToggleRow(x, y, "TCU_SET_BOT", "Telegram Bot API", EnableBotAPIMode);
      TCU_EditRow(x, y, "TGPOLL", "Bot Poll sec", IntegerToString(TelegramPollSeconds));
      TCU_EditRow(x, y, "TGTOKEN", "Bot Token", TelegramBotToken);
      TCU_EditRow(x, y, "TGCHAT", "Chat ID", TelegramChatID);
      TCU_ToggleRow(x, y, "TCU_SET_BRIDGE", "Bridge Mode", EnableBridgeMode);
      TCU_EditRow(x, y, "BRPORT", "Bridge Port", IntegerToString(BridgePort));
      TCU_EditRow(x, y, "BRPOLL", "Bridge Poll ms", IntegerToString(BridgePollMs));
      TCU_ToggleRow(x, y, "TCU_SET_DISCORD", "Discord Send", EnableDiscordMode);
      TCU_EditRow(x, y, "DCWEBHOOK", "Discord Webhook", DiscordWebhookURL);
      TCU_Section(x, y, "COMMAND REPLIES");
      TCU_ToggleRow(x, y, "TCU_SET_CMDREPLY", "React Commands", EnableCommandReplies);
   }
   else if(cat == 1)
   {
      TCU_Section(x, y, "EA-TO-EA COPIER");
      TCU_CycleRow(x, y, "TCU_SET_COPIERMODE", "Copier Mode", TCU_CopierModeText());
      TCU_EditRow(x, y, "COPIERFILE", "CSV File", CopierFileName);
      TCU_ToggleRow(x, y, "TCU_SET_COPIERCLOSE", "Auto-close Slave", CopierAutoClose);
      TCU_EditRow(x, y, "COPIERPOLL", "Poll Speed ms", IntegerToString(CopierPollMs));
      TCU_CycleRow(x, y, "TCU_SET_COPIERSTARTUP", "Startup Copy Mode", TCU_CopierStartupModeText());
      TCU_CycleRow(x, y, "TCU_SET_COPIERLOTMODE", "Slave Lot Mode", TCU_CopierLotModeText());
      TCU_EditRow(x, y, "COPIERFIXED", "Fixed Lot", DoubleToString(CopierFixedLot, 2));
      TCU_EditRow(x, y, "COPIERMULT", "Multiplier", DoubleToString(CopierLotMultiplier, 2));
      TCU_EditRow(x, y, "COPIERRISK", "Risk %", DoubleToString(CopierRiskPercent, 2));
      TCU_EditRow(x, y, "COPIERMAX", "Max Lot", DoubleToString(CopierMaxLot, 2));
      TCU_EditRow(x, y, "COPIERMINLOT", "Minimum Lot To Copy", DoubleToString(CopierMinimumLotToCopy, 2));
      TCU_CycleRow(x, y, "TCU_SET_COPIERCOMMENTMODE", "Comment Mode", TCU_CopierTradeCommentModeText());
      TCU_EditRow(x, y, "COPIERCOMMENT", "Copier Comment", CopierCustomTradeComment);
   }
   else if(cat == 2)
   {
      TCU_Section(x, y, "LOT SIZING & RISK");
      TCU_CycleRow(x, y, "TCU_SET_LOTMODE", "Lot Mode", TCU_LotModeText());
      TCU_AdjustRow(x, y, "FIXEDLOT", "Fixed Lot", DoubleToString(FixedLotSize, 2));
      TCU_AdjustRow(x, y, "RISK", "Risk %", DoubleToString(RiskPercent, 2));
      TCU_AdjustRow(x, y, "DEFSL", "Default SL points", IntegerToString(DefaultSLPoints));
      TCU_AdjustRow(x, y, "MAXLOT", "Max Lot", DoubleToString(MaxLotSize, 2));
      TCU_CycleRow(x, y, "TCU_SET_SKIPLOT", "Over Max Action", SkipIfLotOverMax ? "SKIP TRADE" : "TRIM TO MAX");
      // [v6.00 NEW][PerSymUI] Per-symbol lot overrides: Configure button + live preview
      // (up to 10 entries). Anything past that the user can see in the Configure modal.
      Psl_ParseFromString();
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
      TCU_TextBold(x + 8, y + 7, "Per-Sym Lots", TCU_A(TCUC_TXT), 8);
      string psLabel = IntegerToString(g_pslCount) + " / " + IntegerToString(TCU_PERSYMBOL_MAX) + " -- Configure";
      TCU_Btn("TCU_PSL_OPEN", x + 130, y + 3, TCUC_W - 24 - 130 - 4, 18, psLabel, TCU_A(TCUC_ACC), TCU_A(clrWhite), 8, 4);
      y += 27;
      // Live preview (up to 10) so user sees overrides without opening the modal.
      if(g_pslCount == 0)
      {
         TCU_Row(x, y, "Overrides", "none -- all symbols use Global Lot", TCUC_DIM);
      }
      else
      {
         int psShown = 0;
         for(int psI = 0; psI < g_pslCount && psShown < 10; psI++, psShown++)
         {
            string keyLabel = g_pslKeys[psI];
            string keyResolved = (ArraySize(g_pslResolved) > psI) ? g_pslResolved[psI] : "";
            if(StringLen(keyResolved) > 0 && keyResolved != keyLabel) keyLabel = keyLabel + " (" + keyResolved + ")";
            color rowClr = (StringLen(keyResolved) > 0) ? TCUC_OK : TCUC_DNG;
            TCU_Row(x, y, keyLabel, DoubleToString(g_pslLots[psI], 2), rowClr);
         }
         if(g_pslCount > 10)
            TCU_Row(x, y, "+" + IntegerToString(g_pslCount - 10) + " more", "open Configure", TCUC_DIM);
      }
      // Short note: long version was overflowing the panel.
      TCU_HintText(x + 4, y + 6, "Other symbols use Global Lot Mode.");
      y += 18;
   }
   else if(cat == 3)
   {
      TCU_Section(x, y, "FILTERS & SAFETY");

      if(g_tcuFilterScroll == 0)
      {
         TCU_ToggleRow(x, y, "TCU_SET_SPREAD", "Spread Filter", EnableSpreadFilter);
         TCU_EditRow(x, y, "MAXSPREAD", "Max Spread pts", IntegerToString(MaxSpreadPoints));
         TCU_ToggleRow(x, y, "TCU_SET_SLIP", "Slippage Filter", EnableSlippageFilter);
         TCU_EditRow(x, y, "SLIPPTS", "Slippage pts", IntegerToString(SlippagePoints));
         TCU_EditRow(x, y, "ENTRYSLIP", "Entry Slip pips", DoubleToString(EntrySlippagePips, 1));
         TCU_CycleRow(x, y, "TCU_SET_SLIPACT", "Slippage Action", TCU_SlippageActionText());
         string dupState = EnableDuplicateFilter ? ("ON  " + IntegerToString(DuplicateWindowMinutes) + "m") : "OFF";
         TCU_Btn("TCU_FILTER_DUPLICATE", x, y + 6, TCUC_W - 24, 24,
                 "DUPLICATE FILTER SETTINGS  " + dupState + "  >", TCU_A(C'31,52,82'), TCU_A(TCUC_TXT), 8, 5);
         y += 30;
         string cdState = TCU_CooldownEnabled() ? ("ON  " + IntegerToString(SignalCooldownSeconds / 60) + "m") : "OFF";
         TCU_Btn("TCU_FILTER_COOLDOWN", x, y + 6, TCUC_W - 24, 24,
                 "SIGNAL COOLDOWN  " + cdState + "  >", TCU_A(C'31,52,82'), TCU_A(TCUC_TXT), 8, 5);
         y += 30;
         TCU_HintText(x + 4, y + 8, "Use arrows for symbol lists, skip words, time, duplicate and cooldown.");
      }
      else if(g_tcuFilterScroll == 1)
      {
         TCU_FilterEditBlock(x, y, "TCU_SET_WHITELIST", EnableWhitelist, "WHITELIST",
                             "Whitelist Symbols", "Example: EURUSD,ETHUSD,XAUUSD,BTCUSD,US30", WhitelistSymbols);
         TCU_FilterEditBlock(x, y, "TCU_SET_BLACKLIST", EnableBlacklist, "BLACKLIST",
                             "Blacklist Symbols", "Example: GBPJPY,USDTRY,BTCUSD,DOGEUSD", BlacklistSymbols);
         TCU_FilterEditBlock(x, y, "TCU_SET_SKIPKW", EnableSkipKeywords, "SKIPKW",
                             "Skip Keywords / Phrases", "Example: HIT TP,RUNNING,CLOSED,ANALYSIS,WAIT", SkipKeywords);
      }
      else if(g_tcuFilterScroll == 2)
      {
         TCU_ToggleRow(x, y, "TCU_SET_TIMEFILTER", "Time Filter", EnableTimeFilter);
         TCU_EditRow(x, y, "TIMESTART", "Start Hour", IntegerToString(TimeFilterStartHour));
         TCU_EditRow(x, y, "TIMEEND", "End Hour", IntegerToString(TimeFilterEndHour));
         TCU_TextBold(x + 8, y + 4, "TIME FILTER USES BROKER SERVER TIME", TCU_A(TCUC_DNG), 8);
         y += 22;
      }
      else if(g_tcuFilterScroll == 3)
      {
         TCU_ToggleRow(x, y, "TCU_SET_ARMOUR", "Entry Armour", RequireEntryArmour);
      TCU_NoteText(x + 8, y + 2, "Stricter parser: direction + symbol + SL/TP/entry.");
         y += 16;
         TCU_CompactEditBlock(x, y, "CUSTOMMAP", "Custom Symbol Mappings",
                              "Example: GOLD=XAUUSD,US30=DJI30,BTC=BTCUSD", CustomMappings);
         TCU_ToggleRow(x, y, "TCU_SET_KWREPLACE", "Keyword Replace", EnableKeywordReplace);
         TCU_CompactEditBlock(x, y, "KWREPLACE", "Keyword Replace Map",
                              "Example: Stoploss=SL,Take Profit=TP,Target=TP", KeywordReplaceMap);
         TCU_ToggleRow(x, y, "TCU_SET_CMDREPLY", "Command Replies", EnableCommandReplies);
         TCU_EditRow(x, y, "MOVESLCMD", "Move SL Commands", MoveSLCommands);
         TCU_EditRow(x, y, "CLOSEALLCMD", "Close All Commands", CloseAllCommands);
      }
      else if(g_tcuFilterScroll == 4)
      {
         TCU_Section(x, y, "SIGNAL COOLDOWN");
         TCU_ToggleRow(x, y, "TCU_SET_COOLDOWN", "Cooldown", TCU_CooldownEnabled());
         TCU_EditRow(x, y, "COOLDOWN", "Cooldown min", IntegerToString(SignalCooldownSeconds / 60));
         TCU_ToggleRow(x, y, "TCU_SET_SLTPINCD", "Allow SL/TP in Cooldown", AllowSLTPModDuringCooldown);
         TCU_NoteText(x + 8, y + 2, "ON blocks duplicate same-direction signals for this symbol.");
         y += 12;
         TCU_NoteText(x + 8, y + 2, "ON + Allow SL/TP lets follow-up signals modify inside cooldown.");
         y += 12;
         TCU_NoteText(x + 8, y + 2, "OFF means same-direction signals can open new trades normally.");
         y += 16;
      }
      else if(g_tcuFilterScroll == 5)
      {
         TCU_Section(x, y, "DUPLICATE FILTER");
         TCU_ToggleRow(x, y, "TCU_SET_DUP", "Duplicate Filter", EnableDuplicateFilter);
         TCU_EditRow(x, y, "DUPWIN", "Duplicate Window min", IntegerToString(DuplicateWindowMinutes));
         TCU_NoteText(x + 8, y + 2, "Blocks the same exact signal text only inside this replay window.");
         y += 12;
         TCU_NoteText(x + 8, y + 2, "Useful for resend glitches, forwarding echoes, and startup replays.");
         y += 12;
         TCU_NoteText(x + 8, y + 2, "After the window expires, the same text can trade again normally.");
         y += 16;
      }

      int navY = TCUC_H - 94;
      TCU_FillRoundRectAA(x, navY - 22, TCUC_W - 24, 20, 5, TCU_A(C'13,17,27'));
      TCU_Text(x + 104, navY - 16, "FILTER PAGE " + IntegerToString(g_tcuFilterScroll + 1) + " / 6", TCU_A(TCUC_DIM), 7);
      TCU_Btn("TCU_FILTER_UP", x, navY, 160, 28, "< PREVIOUS",
              TCU_A(g_tcuFilterScroll > 0 ? C'31,52,82' : TCUC_GRID), TCU_A(g_tcuFilterScroll > 0 ? TCUC_TXT : TCUC_DIM), 7, 5);
      TCU_Btn("TCU_FILTER_DOWN", x + 168, navY, 160, 28, "NEXT >",
              TCU_A(g_tcuFilterScroll < 5 ? C'31,52,82' : TCUC_GRID), TCU_A(g_tcuFilterScroll < 5 ? TCUC_TXT : TCUC_DIM), 7, 5);
      }
   else if(cat == 4)
   {
      TCU_Section(x, y, "TRADE EXECUTION");
      TCU_ToggleRow(x, y, "TCU_SET_ARM", "Arm Execution", ArmExecution);
      TCU_ToggleRow(x, y, "TCU_SET_REVERSE", "Reverse Signal", ReverseSignal);
      TCU_ToggleRow(x, y, "TCU_SET_COPYSL", "Copy SL", CopySL);
      TCU_ToggleRow(x, y, "TCU_SET_COPYTP", "Copy TP", CopyTP);
      TCU_CycleRow(x, y, "TCU_SET_OPPACT", "Opposite Action", TCU_OppositeActionText());
      TCU_NoteText(x + 8, y + 2, "Opposite signal: keep, close opposite, or close all.");
      y += 16;
      TCU_ToggleRow(x, y, "TCU_SET_PENDING", "Pending Orders", EnablePendingOrders);
      TCU_ToggleRow(x, y, "TCU_SET_PEXP", "Pending Expiry", EnablePendingExpiry);
      TCU_EditRow(x, y, "PEXPHOURS", "Expiry Hours", IntegerToString(PendingExpiryHours));
      TCU_ToggleRow(x, y, "TCU_SET_MODSTACK", "Update SL/TP in Cooldown", AllowSLTPModDuringCooldown);
      TCU_NoteText(x + 8, y + 2, "ON = same-side follow-ups update SL/TP during cooldown.");
      y += 16;
      TCU_EditRow(x, y, "MINPIPSDIST", "Min Same Pips", DoubleToString(MinPipsDistanceSameType, 1));
      TCU_NoteText(x + 8, y + 2, "Blocks same-side entries too close together.");
      y += 16;
   }
   else if(cat == 5)
   {
      TCU_Section(x, y, "AUTO SL / TP");
      TCU_ToggleRow(x, y, "TCU_SET_AUTOSL", "Auto SL", EnableAutoSL);
      TCU_EditRow(x, y, "FALLSL", "Fallback SL pips", IntegerToString(FallbackSLPips));
      TCU_ToggleRow(x, y, "TCU_SET_AUTOTP", "Auto TP", EnableAutoTP);
      TCU_EditRow(x, y, "FALLTP", "Fallback TP pips", IntegerToString(FallbackTPPips));
      TCU_ToggleRow(x, y, "TCU_SET_CUSTOMSLTP", "Custom SL/TP Keywords", EnableCustomSLTPKeywords);
      TCU_EditRow(x, y, "CUSTOMSLKW", "SL Keywords", CustomSLKeywords);
      TCU_EditRow(x, y, "CUSTOMTPKW", "TP Keywords", CustomTPKeywords);
      TCU_EditRow(x, y, "BEBUFFER", "BE Buffer pips", IntegerToString(BreakevenBufferPips));
      TCU_NoteText(x + 8, y + 2, "Breakeven SL locks entry +/- this many pips.");
      y += 16;
   }
   else if(cat == 6)
   {
      TCU_Section(x, y, "SIGNAL TP");
      TCU_ToggleRow(x, y, "TCU_SET_SIGNALTP", "Use Signal TP", EnableSignalTP);
      TCU_ToggleRow(x, y, "TCU_SET_MULTITP", "Multi-TP Split", EnableMultiTP);
      TCU_NoteText(x + 8, y + 2, "AUTO Partials Scope ignores split TP trades.");
      y += 16;
      TCU_ToggleRow(x, y, "TCU_SET_PENDMTP", "Pending Multi-TP", EnablePendingMultiTP);
      TCU_EditRow(x, y, "MAXTPS", "Max Signal TPs", IntegerToString(MaxTPTargets));
      TCU_CycleRow(x, y, "TCU_SIGTP_MODE", "Alloc Mode", SignalTpAllocMode == PARTIAL_FIXED_LOTS ? "LOTS" : "PERCENT");
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 22, 4, TCU_A(C'13,17,27'));
      TCU_Text(118, y + 6, "Alloc", TCU_A(TCUC_DIM), 7);
      TCU_Text(238, y + 6, "Mode", TCU_A(TCUC_DIM), 7);
      TCU_Text(294, y + 6, "ON", TCU_A(TCUC_DIM), 7);
      y += 25;
      TCU_SignalTpGridRow(y, 1);
      TCU_SignalTpGridRow(y, 2);
      TCU_SignalTpGridRow(y, 3);
      y += 4;
      TCU_NoteText(x + 8, y + 2, SignalTpAllocMode == PARTIAL_FIXED_LOTS ? "FIXED LOTS open exact TP lots and override main lot size." : "PERCENT splits the main lot across TP legs.");
      y += 16;
      TCU_ToggleRow(x, y, "TCU_SET_TGBE", "SL -> BE on TP1", TGMoveSLBreakevenTP1);
      TCU_EditRow(x, y, "TGBEEXTRA", "BE Extra Pips", IntegerToString(TGBreakevenExtraPips));
      TCU_ToggleRow(x, y, "TCU_SET_TGTP1", "SL -> TP1 on TP2", TGMoveSLToTP1OnTP2);
   }
   else if(cat == 7)
   {
      TCU_Section(x, y, "TRAILING STOP");
      TCU_ToggleRow(x, y, "TCU_SET_TRAIL", "Trailing Stop", EnableTrailingStop);
      TCU_EditRow(x, y, "TRAILSTART", "Trail Start", IntegerToString(TrailStartPips));
      TCU_EditRow(x, y, "TRAILDIST", "Trail Distance", IntegerToString(TrailDistancePips));
      TCU_EditRow(x, y, "TRAILSTEP", "Trail Step", IntegerToString(TrailStepPips));
      TCU_ToggleRow(x, y, "TCU_SET_TRAILBE", "Move To Breakeven", TrailMoveToBreakeven);
      TCU_EditRow(x, y, "BEBUFFER", "BE Buffer pips", IntegerToString(BreakevenBufferPips));
   }
   else if(cat == 9)
   {
      TCU_Section(x, y, "PARTIALS");
      TCU_ToggleRow(x, y, "TCU_SET_PARTIAL", "Global Partials", EnablePartialClose);
      TCU_CycleRow(x, y, "TCU_SET_PARTSCOPE", "Partials Scope", TCU_PartialScopeText());
      TCU_NoteText(x + 8, y + 2, "AUTO = ignore signal Multi-TP trades. ALL = partial every tracked trade.");
      y += 16;
      TCU_CycleRow(x, y, "TCU_PART_MODE", "Close Mode", PartialCloseMode == PARTIAL_FIXED_LOTS ? "LOTS" : "PERCENT");
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 22, 4, TCU_A(C'13,17,27'));
      TCU_Text(72, y + 6, "Pips", TCU_A(TCUC_DIM), 7);
      TCU_Text(132, y + 6, PartialCloseMode == PARTIAL_FIXED_LOTS ? "Lots" : "Close %", TCU_A(TCUC_DIM), 7);
      TCU_Text(198, y + 6, "Move SL", TCU_A(TCUC_DIM), 7);
      TCU_Text(294, y + 6, "ON", TCU_A(TCUC_DIM), 7);
      y += 25;
      TCU_PartialGridRow(y, 1, PartialTP1Pips, PartialCloseMode == PARTIAL_FIXED_LOTS ? PartialTP1Lots : PartialTP1Percent,
                         PartialTP1Pips > 0, "->BE", PartialMoveSLBreakeven);
      TCU_PartialGridRow(y, 2, PartialTP2Pips, PartialCloseMode == PARTIAL_FIXED_LOTS ? PartialTP2Lots : PartialTP2Percent,
                         PartialTP2Pips > 0, "->TP1", PartialMoveSLToTP1);
      TCU_PartialGridRow(y, 3, PartialTP3Pips, PartialCloseMode == PARTIAL_FIXED_LOTS ? PartialTP3Lots : PartialTP3Percent,
                         PartialTP3Pips > 0, "->TP2", PartialMoveSLToTP2);
      TCU_PartialGridRow(y, 4, PartialTP4Pips, PartialCloseMode == PARTIAL_FIXED_LOTS ? PartialTP4Lots : PartialTP4Percent,
                         PartialTP4Pips > 0, "->TP3", PartialMoveSLToTP3);
      y += 4;
      TCU_EditRow(x, y, "PBEEXTRA", "BE Extra Pips", IntegerToString(PartialBEExtraPips));
      TCU_NoteText(x + 8, y + 2, "Use AUTO if Signal TP splitting is also enabled.");
      y += 16;
   }
   else if(cat == 8)
   {
      TCU_Section(x, y, "NEWS PAUSE");
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 34, 6, TCU_A(TCUC_CARD));
      TCU_TextBold(x + 8, y + 12, "IMPACT FILTER", TCU_A(TCUC_DIM), 7);
      TCU_Btn("TCU_NEWS_IMPACT_ALL", x + 96, y + 6, 42, 22, "ALL",
              TCU_A((NewsPauseHighImpact && NewsPauseMediumImpact) ? TCUC_ACC : TCUC_GRID), TCU_A(TCUC_TXT), 7, 4);
      TCU_Btn("TCU_NEWS_IMPACT_HIGH", x + 144, y + 6, 50, 22, "HIGH",
              TCU_A((NewsPauseHighImpact && !NewsPauseMediumImpact) ? TCUC_ACC : TCUC_GRID), TCU_A(TCUC_TXT), 7, 4);
      TCU_Btn("TCU_NEWS_IMPACT_MED", x + 200, y + 6, 44, 22, "MED",
              TCU_A((!NewsPauseHighImpact && NewsPauseMediumImpact) ? TCUC_ACC : TCUC_GRID), TCU_A(TCUC_TXT), 7, 4);
      TCU_Btn("TCU_NEWS_LOAD", x + 252, y + 6, 72, 22, "Reload", TCU_A(C'31,52,82'), TCU_A(TCUC_ACC), 7, 4);
      y += 40;

      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 54, 6, TCU_A(TCUC_CARD));
      TCU_TextBold(x + 8, y + 7, "CURRENCIES TO WATCH", TCU_A(TCUC_DIM), 7);
      int cw = (TCUC_W - 42) / 8;
      for(int ci = 0; ci < 8; ci++)
      {
         string cur = TCU_NewsCurrencyByIndex(ci);
         bool on = TCU_CsvHasWord(NewsPauseCurrencies, cur);
         TCU_Btn("TCU_NEWS_CUR_" + cur, x + 8 + ci * cw, y + 27, cw - 2, 20, cur,
                 TCU_A(on ? TCUC_ACC : TCUC_GRID), TCU_A(on ? clrWhite : TCUC_DIM), 6, 3);
      }
      y += 60;

      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 46, 6, TCU_A(TCUC_CARD));
      TCU_Text(x + 8, y + 7, "Extra currencies", TCU_A(TCUC_DIM), 7);
      TCU_HintText(x + 112, y + 7, "Example: SGD,ZAR,CNY");
      TCU_EditBoxLarge("NEWSEXTRA", x + 8, y + 23, TCUC_W - 40, 18, TCU_NewsExtraCurrencies());
      y += 52;

      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 34, 6, TCU_A(TCUC_CARD));
      TCU_Text(x + 8, y + 11, "Before min", TCU_A(TCUC_DIM), 7);
      TCU_EditBox("NEWSBEFORE", x + 52, y + 7, 34, IntegerToString(NewsPauseBeforeMinutes));
      TCU_Text(x + 92, y + 11, "After min", TCU_A(TCUC_DIM), 7);
      TCU_EditBox("NEWSAFTER", x + 138, y + 7, 34, IntegerToString(NewsPauseAfterMinutes));
      TCU_Btn("TCU_SET_NEWSPAUSE", x + 184, y + 6, 64, 22, EnableNewsPause ? "PAUSE ON" : "OFF",
              TCU_A(EnableNewsPause ? TCUC_OK : C'96,32,50'), TCU_A(TCUC_TXT), 7, 4);
      TCU_Btn("TCU_NEWS_LOAD", x + 254, y + 6, 70, 22, "LOAD", TCU_A(C'31,52,82'), TCU_A(TCUC_TXT), 7, 4);
      y += 40;

      string stat = "Loaded: " + IntegerToString(g_tcuNewsCount);
      if(g_tcuNewsLastLoad > 0) stat += "  |  " + TimeToString(g_tcuNewsLastLoad, TIME_MINUTES);
      TCU_FillRoundRectAA(x, y, TCUC_W - 24, 20, 4, TCU_A(C'13,17,27'));
      TCU_Text(x + 8, y + 5, stat, TCU_A(g_tcuNewsCount > 0 ? TCUC_ACC : TCUC_DIM), 7);
      y += 26;

      TCU_Section(x, y, "UPCOMING EVENTS");
      int total = 0;
      datetime now = TimeCurrent();
      for(int ni = 0; ni < g_tcuNewsCount; ni++)
      {
         if(g_tcuNews[ni].time < now - 3600) continue;
         total++;
      }

      int maxRows = 3;
      if(g_tcuNewsScroll > MathMax(0, total - maxRows)) g_tcuNewsScroll = MathMax(0, total - maxRows);
      int skipped = 0, shown = 0;
      for(int ni = 0; ni < g_tcuNewsCount && shown < maxRows; ni++)
      {
         if(g_tcuNews[ni].time < now - 3600) continue;
         if(skipped < g_tcuNewsScroll) { skipped++; continue; }
         string stars = (g_tcuNews[ni].impact >= 3) ? "***" : "**";
         TCU_FillRoundRectAA(x, y, TCUC_W - 24, 24, 4, TCU_A(TCUC_CARD));
         TCU_TextBold(x + 8, y + 7, stars, TCU_A(g_tcuNews[ni].impact >= 3 ? TCUC_DNG : TCUC_WARN), 7);
         TCU_Text(x + 34, y + 7, TimeToString(g_tcuNews[ni].time, TIME_MINUTES), TCU_A(TCUC_TXT), 7);
         TCU_TextBold(x + 76, y + 7, g_tcuNews[ni].currency, TCU_A(TCUC_WARN), 7);
         TCU_Text(x + 116, y + 7, TCU_Short(g_tcuNews[ni].name, 25), TCU_A(TCUC_TXT), 6);
         y += 27;
         shown++;
      }
      if(shown == 0)
      {
         TCU_FillRoundRectAA(x, y, TCUC_W - 24, 28, 5, TCU_A(TCUC_CARD));
         TCU_Text(x + 8, y + 9, g_tcuNewsLastLoad > 0 ? "No matching events loaded." : "Press LOAD to show MT5 calendar events.", TCU_A(TCUC_DIM), 7);
         y += 32;
      }
      bool canUp = (g_tcuNewsScroll > 0);
      bool canDown = (g_tcuNewsScroll + maxRows < total);
      int arrY = TCUC_H - 36;
      TCU_FillRoundRectAA(x, arrY - 4, TCUC_W - 24, 28, 6, TCU_A(TCUC_PNL));
      TCU_Btn("TCU_NEWS_UP", x + 126, arrY, 48, 18, "^", TCU_A(canUp ? TCUC_GRID : C'18,22,34'), TCU_A(canUp ? TCUC_TXT : TCUC_DIM), 8, 4);
      TCU_Btn("TCU_NEWS_DOWN", x + 184, arrY, 48, 18, "v", TCU_A(canDown ? TCUC_GRID : C'18,22,34'), TCU_A(canDown ? TCUC_TXT : TCUC_DIM), 8, 4);
   }
   else if(cat == 10)
   {
      TCU_Section(x, y, "ALERTS & BROADCAST");
      TCU_ToggleRow(x, y, "TCU_SET_POPUP", "Popup Alerts", EnablePopupAlerts);
      TCU_ToggleRow(x, y, "TCU_SET_SOUND", "Sound Alerts", EnableSoundAlerts);
      TCU_EditRow(x, y, "SOUNDFILE", "Sound File", AlertSoundFile);
      TCU_ToggleRow(x, y, "TCU_SET_PUSH", "Push Notify", EnablePushNotify);
      TCU_ToggleRow(x, y, "TCU_SET_PARTALERT", "Partial Alerts", EnablePartialAlerts);
      TCU_ToggleRow(x, y, "TCU_SET_CMDREPLY", "Command Replies", EnableCommandReplies);
      TCU_NoteText(x + 8, y + 2, "OFF = ignore close/breakeven command messages.");
      y += 16;
      TCU_ToggleRow(x, y, "TCU_SET_TGSEND2", "Telegram Broadcast", EnableTelegramSend);
      TCU_EditRow(x, y, "TGTAG", "Broadcast Tag", TelegramSendTag);
      TCU_EditRow(x, y, "TGSUFFIX", "Broadcast Suffix", TelegramSendSuffix);
      TCU_ToggleRow(x, y, "TCU_SET_SENDBOT", "Separate Send Bot", UseSeparateSendBot);
      TCU_NoteText(x + 8, y + 2, "Sends alerts to another Telegram channel/group.");
      y += 16;
      if(UseSeparateSendBot)
      {
         TCU_EditRow(x, y, "SENDBOT", "Send Bot Token", SendBotToken);
         TCU_EditRow(x, y, "SENDCHAT", "Send Chat ID", SendChatID);
      }
   }
   else if(cat == 11)
   {
      TCU_Section(x, y, "PROP FIRM PROTECTION");
      TCU_ToggleRow(x, y, "TCU_SET_PROP", "Prop Firm Mode", PropFirmMode);
      TCU_NoteText(x + 8, y + 2, "ON = no trade comments, forces safer prop limits.");
      y += 16;
      TCU_ToggleRow(x, y, "TCU_SET_SKIPNOSL", "Require SL", SkipSignalWithoutSL);
      TCU_ToggleRow(x, y, "TCU_SET_SKIPNOTP", "Require TP", SkipSignalWithoutTP);
      TCU_EditRow(x, y, "MAXOPENPOS", "Max Open Positions", IntegerToString(MaxOpenPositions));
      TCU_EditRow(x, y, "MAXTRADESMIN", "Max Trades / min", IntegerToString(MaxTradesPerMinute));
      TCU_EditRow(x, y, "DAILYLOSSPCT", "Daily Loss %", DoubleToString(MaxDailyLossPercent, 2));
      TCU_EditRow(x, y, "DAILYLOSSAMT", "Daily Loss $", DoubleToString(MaxDailyLossAmount, 2));
      TCU_ToggleRow(x, y, "TCU_SET_SPREAD", "Spread Filter", EnableSpreadFilter);
      TCU_EditRow(x, y, "MAXSPREAD", "Max Spread pts", IntegerToString(MaxSpreadPoints));
   }
   else
   {
      TCU_Section(x, y, "SYSTEM");
      TCU_EditRow(x, y, "MAGIC", "Magic Number", IntegerToString(MagicNumber));
      TCU_ToggleRow(x, y, "TCU_SET_DIAG", "Diagnostic Log", EnableDiagLog);
      TCU_EditRow(x, y, "DIAGFILE", "Diag File", DiagLogFileName);
      TCU_ToggleRow(x, y, "TCU_SET_REPORT", "Report Log", EnableReportLog);
      TCU_EditRow(x, y, "PURGEDAYS", "Report Purge Days", IntegerToString(ReportPurgeDays));
      TCU_ToggleRow(x, y, "TCU_SET_RESTARTDISARM", "MT5 Restart Disarms EA", DisarmOnRestart);
      TCU_NoteText(x + 8, y + 2, "OFF = MT5 close/reopen may restore ARM.");
      y += 12;
      TCU_NoteText(x + 8, y + 2, "Fresh EA attachments still start DISARMED.");
      y += 16;
      TCU_EditRow(x, y, "SYMSUFFIX", "Symbol Suffix", SymbolSuffix);
      TCU_InfoRow(x, y, "Last Error", StringLen(g_lastError) > 0 ? g_lastError : "Ready");
      TCU_HintText(x + 4, y + 8, "Click a field, type, press Enter. It saves immediately.");
   }
}

void TCU_DrawFooter()
{
   if(g_tcuTab == 9 || g_tcuTab == 13) return;
   int y = TCUC_H - 44;
   TCU_FillRoundRectAA(8, y, TCUC_W - 16, 34, 8, TCU_A(TCUC_PNL));
   if(g_tcuTab == 5)
   {
      TCU_Text(16, y + 10, "Cmd Replies", TCU_A(TCUC_DIM), 6);
      TCU_Btn("TCU_SET_CMDREPLIES", 110, y + 6, 66, 22,
              EnableCommandReplies ? "ON" : "OFF",
              TCU_A(EnableCommandReplies ? C'0,112,73' : C'96,32,50'),
              TCU_A(TCUC_TXT), 7, 4);
   }
   else
   {
      string footer = (ArmExecution ? "ARMED" : "DISARMED") +
                      "  SL:" + IntegerToString(FallbackSLPips) +
                      "  TP:" + IntegerToString(FallbackTPPips) +
                      "  Lot:" + DoubleToString(FixedLotSize, 2);
      TCU_Text(16, y + 10, footer, TCU_A(TCUC_DIM), 6);
   }
   TCU_Btn("TCU_PROF_TOGGLE", TCUC_W - 170, y + 6, 82, 22,
           "PROFILES", TCU_A(g_tcuProfileOpen ? TCUC_ACC : C'28,42,66'),
           TCU_A(g_tcuProfileOpen ? TCUC_TXT : TCUC_DIM), 7, 4);
   TCU_DrawPill(TCUC_W - 82, y + 7, 70, 20, "AUTO SAVE", C'31,52,82', TCUC_ACC, 6);
}

void TCU_DestroyMonitorPopup()
{
   if(g_tcuMonCreated)
   {
      g_tcuMonCanvas.Destroy();
      g_tcuMonCreated = false;
   }
   ObjectDelete(0, TCUC_PFX + "MON_CV");
   g_tcuMonHitCount = 0;
   ArrayResize(g_tcuMonHits, 0);
}

// ============================================================
// [MG Monitor] Martingale Monitor popup
// ============================================================
void TCU_DestroyMGMonitor()
{
   if(g_mgmCreated) { g_mgmCanvas.Destroy(); g_mgmCreated = false; }
   ObjectDelete(0, TCUC_PFX + "MGM_CV");
   g_mgmHitCount = 0;
   ArrayResize(g_mgmHits, 0);
}

void TCU_OpenMGMonitor()
{
   g_mgmOpen = true;
   if(g_mgmX < 0 || g_mgmY < 0)
   {
      int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
      int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
      g_mgmX = g_panelX + g_panelW + 10;
      if(g_mgmX + TCU_MGM_W > chartW - 10)
         g_mgmX = MathMax(10, g_panelX - TCU_MGM_W - 10);
      g_mgmY = g_panelY + 30;
      if(g_mgmY + TCU_MGM_H > chartH - 10)
         g_mgmY = MathMax(10, chartH - TCU_MGM_H - 10);
   }
}

void TCU_DrawMGMonitorList(int x, int &y)
{
   int _monActive = 0;
   for(int _c = 0; _c < g_mgCount; _c++)
      if(g_mgTable[_c].streak != 0 || g_mgTable[_c].mgPnl != 0) _monActive++;

   string subhdr = _monActive > 0
      ? IntegerToString(_monActive) + " symbol(s) tracked - click row for details"
      : "Waiting for closed trades to appear here";
   TCU_MGMFillRoundRect(x, y, TCU_MGM_W-20, 24, 5, TCU_A(C'13,17,27'));
   TCU_MGMText(x+10, y+6, subhdr, TCU_A(TCUC_DIM), 7);
   y += 28;

   if(_monActive == 0)
   {
      TCU_MGMFillRoundRect(x, y, TCU_MGM_W-20, 80, 7, TCU_A(TCUC_CARD, 248));
      TCU_MGMTextBold(x+12, y+14, "No data yet", TCU_A(TCUC_TXT), 9);
      TCU_MGMText(x+12, y+38, "Martingale tracks each symbol after", TCU_A(TCUC_DIM), 7);
      TCU_MGMText(x+12, y+52, "the first closed trade.", TCU_A(TCUC_DIM), 7);
      return;
   }

   TCU_MGMFillRoundRect(x, y, TCU_MGM_W-20, 20, 4, TCU_A(C'18,22,34'));
   TCU_MGMText(x+8,   y+5, "Symbol",  TCU_A(TCUC_DIM), 7);
   TCU_MGMText(x+138, y+5, "Streak",  TCU_A(TCUC_DIM), 7);
   TCU_MGMText(x+200, y+5, "Cum P&L", TCU_A(TCUC_DIM), 7);
   TCU_MGMText(x+290, y+5, "Status",  TCU_A(TCUC_DIM), 7);
   y += 24;

   int maxRows = 9;
   int total = g_mgCount;
   if(g_mgmScroll > MathMax(0, _monActive - maxRows)) g_mgmScroll = MathMax(0, _monActive - maxRows);
   int _skip = 0; int _rendered = 0;
   for(int i = 0; i < total && _rendered < maxRows; i++)
   {
      bool hasStreak  = (g_mgTable[i].streak > 0);
      bool recovering = (EnableMartingale && MartingaleMode == 4 && hasStreak);
      double pnl = g_mgTable[i].mgPnl;
      if(g_mgTable[i].streak == 0 && pnl == 0) continue;
      if(_skip < g_mgmScroll) { _skip++; continue; }
      _rendered++;

      uint rowBg = TCU_A(recovering ? C'40,25,10' : TCUC_CARD, 248);
      TCU_MGMFillRoundRect(x, y, TCU_MGM_W-20, 36, 6, rowBg);

      TCU_MGMTextBold(x+8, y+8, g_mgTable[i].sym, TCU_A(TCUC_TXT), 8);

      string streakStr = hasStreak ? IntegerToString(g_mgTable[i].streak) + "L" : "-";
      TCU_MGMTextBold(x+138, y+8, streakStr, TCU_A(hasStreak ? TCUC_WARN : TCUC_DIM), 7);

      string pnlStr = (pnl >= 0 ? "+" : "") + DoubleToString(pnl, 2);
      TCU_MGMTextBold(x+200, y+8, pnlStr, TCU_A(pnl >= 0 ? TCUC_OK : TCUC_DNG), 7);

      string status = recovering ? "RECOVERING" : (hasStreak ? "IN STREAK" : "IDLE");
      uint stClr    = recovering ? TCU_A(TCUC_WARN) : (hasStreak ? TCU_A(TCUC_ACC) : TCU_A(TCUC_DIM));
      TCU_MGMText(x+290, y+8, status, stClr, 7);

      string wlStr = "W:" + IntegerToString(g_mgTable[i].wins) + "  L:" + IntegerToString(g_mgTable[i].losses);
      TCU_MGMText(x+8, y+22, wlStr, TCU_A(TCUC_DIM), 6);
      if(g_mgTable[i].lastPnl != 0)
      {
         string lastStr = "Last " + (g_mgTable[i].lastPnl >= 0 ? "+" : "") + DoubleToString(g_mgTable[i].lastPnl, 2);
         TCU_MGMText(x+80, y+22, lastStr, TCU_A(g_mgTable[i].lastPnl >= 0 ? TCUC_OK : TCUC_DNG), 6);
      }

      TCU_MGMRegHit("TCU_MGM_ROW_" + IntegerToString(i), x, y, TCU_MGM_W-20, 36);
      y += 40;
   }

   if(total > maxRows)
   {
      bool canUp = (g_mgmScroll > 0);
      bool canDn = (g_mgmScroll + maxRows < total);
      TCU_MGMBtn("TCU_MGM_UP", x+148, y+4, 36, 18, "^", TCU_A(canUp ? TCUC_GRID : C'18,22,34'), TCU_A(canUp ? TCUC_TXT : TCUC_DIM), 8, 4);
      TCU_MGMBtn("TCU_MGM_DN", x+192, y+4, 36, 18, "v", TCU_A(canDn ? TCUC_GRID : C'18,22,34'), TCU_A(canDn ? TCUC_TXT : TCUC_DIM), 8, 4);
   }
}

void TCU_DrawMGMonitorDetail(int x, int &y)
{
   int idx = g_mgmSelected;
   string sym = g_mgTable[idx].sym;
   bool hasStreak  = (g_mgTable[idx].streak > 0);
   bool recovering = (EnableMartingale && MartingaleMode == 4 && hasStreak);
   double pnl = g_mgTable[idx].mgPnl;

   TCU_MGMBtn("TCU_MGM_BACK", x, y, 52, 22, "< BACK", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 7, 4);
   TCU_MGMTextBold(x+60, y+5, sym, TCU_A(TCUC_TXT), 10);
   string modeTag = EnableMartingale ? MG_ModeText() : "OFF";
   TCU_MGMText(x+60, y+18, modeTag, TCU_A(TCUC_DIM), 6);
   y += 32;

   int cardH = recovering ? 110 : 90;
   TCU_MGMFillRoundRect(x, y, TCU_MGM_W-20, cardH, 7, TCU_A(TCUC_CARD, 248));

   TCU_MGMText(x+10, y+10, "Streak:",    TCU_A(TCUC_DIM), 7);
   string stStr = hasStreak ? IntegerToString(g_mgTable[idx].streak) + " loss(es)" : "0  (clean)";
   TCU_MGMTextBold(x+64, y+10, stStr, TCU_A(hasStreak ? TCUC_WARN : TCUC_OK), 7);

   TCU_MGMText(x+196, y+10, "Cum P&L:", TCU_A(TCUC_DIM), 7);
   string pnlStr = (pnl >= 0 ? "+" : "") + DoubleToString(pnl, 2);
   TCU_MGMTextBold(x+254, y+10, pnlStr, TCU_A(pnl >= 0 ? TCUC_OK : TCUC_DNG), 7);

   TCU_MGMText(x+10, y+30, "Session W:", TCU_A(TCUC_DIM), 7);
   TCU_MGMTextBold(x+74, y+30, IntegerToString(g_mgTable[idx].wins), TCU_A(TCUC_OK), 8);
   TCU_MGMText(x+196, y+30, "Session L:", TCU_A(TCUC_DIM), 7);
   TCU_MGMTextBold(x+254, y+30, IntegerToString(g_mgTable[idx].losses), TCU_A(TCUC_DNG), 8);

   string lastStr = (g_mgTable[idx].lastPnl != 0)
      ? (g_mgTable[idx].lastPnl >= 0 ? "+" : "") + DoubleToString(g_mgTable[idx].lastPnl, 2)
      : "-";
   TCU_MGMText(x+10, y+50, "Last trade:", TCU_A(TCUC_DIM), 7);
   TCU_MGMTextBold(x+78, y+50, lastStr, TCU_A(g_mgTable[idx].lastPnl >= 0 ? TCUC_OK : TCUC_DNG), 7);

   if(recovering)
   {
      double _carry = (idx >= 0) ? g_mgTable[idx].carry : 0;
      TCU_MGMFillRoundRect(x+6, y+68, TCU_MGM_W-32, 18, 4, TCU_A(C'48,28,8'));
      string recStr = "Recovery active  --  carry to recover: $" + DoubleToString(_carry, 2);
      TCU_MGMText(x+12, y+72, recStr, TCU_A(TCUC_WARN), 7);
   }
   y += cardH + 8;

   TCU_MGMBtn("TCU_MGM_RESET_SYM", x, y, 72, 22, "RESET", TCU_A(C'55,25,25'), TCU_A(TCUC_TXT), 7, 4);
   TCU_MGMText(x+80, y+6, "Clears streak & P&L for this symbol", TCU_A(TCUC_DIM), 7);
   y += 30;

   TCU_MGMFillRoundRect(x, y, TCU_MGM_W-20, 20, 4, TCU_A(C'13,17,27'));
   TCU_MGMTextBold(x+10, y+5, "TRADE HISTORY  (this session, newest first)", TCU_A(TCUC_ACC), 7);
   y += 24;

   int count = 0;
   for(int i = 0; i < g_mgHistCount; i++)
      if(g_mgHistSym[i] == sym) count++;

   if(count == 0)
   {
      TCU_MGMFillRoundRect(x, y, TCU_MGM_W-20, 36, 5, TCU_A(TCUC_CARD, 248));
      TCU_MGMText(x+12, y+12, "No closed trades recorded this session yet.", TCU_A(TCUC_DIM), 7);
      return;
   }

   int shown = 0, maxShow = 7;
   for(int i = g_mgHistCount-1; i >= 0 && shown < maxShow; i--)
   {
      if(g_mgHistSym[i] != sym) continue;
      double hp = g_mgHistProfit[i];
      bool win = (hp >= 0);
      TCU_MGMFillRoundRect(x, y, TCU_MGM_W-20, 26, 5, TCU_A(win ? C'14,34,22' : C'38,14,14', 240));
      TCU_MGMTextBold(x+8, y+7, win ? "WIN" : "LOSS", TCU_A(win ? TCUC_OK : TCUC_DNG), 7);
      TCU_MGMTextBold(x+56, y+7, (hp >= 0 ? "+" : "") + DoubleToString(hp, 2), TCU_A(win ? TCUC_OK : TCUC_DNG), 8);
      TCU_MGMText(x+180, y+7, TimeToString(g_mgHistTime[i], TIME_DATE|TIME_MINUTES), TCU_A(TCUC_DIM), 7);
      y += 28;
      shown++;
   }
}

void TCU_DrawMGMonitor()
{
   if(!g_mgmOpen) { TCU_DestroyMGMonitor(); return; }

   string name = TCUC_PFX + "MGM_CV";
   if(g_mgmCreated)
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_mgmX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_mgmY);
      g_mgmCanvas.Erase(0x00000000);
   }
   else
   {
      g_mgmCanvas.CreateBitmapLabel(0, 0, name, g_mgmX, g_mgmY, TCU_MGM_W, TCU_MGM_H, COLOR_FORMAT_ARGB_NORMALIZE);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 6);
      g_mgmCanvas.Erase(0x00000000);
      g_mgmCreated = true;
   }

   g_mgmHitCount = 0;
   ArrayResize(g_mgmHits, 0);

   TCU_MGMFillRoundRect(0, 0, TCU_MGM_W, TCU_MGM_H, 10, TCU_A(TCUC_BRD, 250));
   TCU_MGMFillRoundRect(1, 1, TCU_MGM_W-2, TCU_MGM_H-2, 9, TCU_A(TCUC_BG, 248));
   TCU_MGMFillRoundRect(1, 1, TCU_MGM_W-2, 36, 9, TCU_A(TCUC_PNL, 252));

   TCU_MGMTextBold(12, 11, "MARTINGALE MONITOR", TCU_A(TCUC_TXT), 9);
   string modeTag = EnableMartingale ? ("MODE: " + MG_ModeText()) : "MG: OFF";
   uint modeBg = EnableMartingale ? (MartingaleMode == 4 ? TCU_A(C'72,38,8') : TCU_A(C'14,48,72')) : TCU_A(C'36,18,18');
   uint modeFg = EnableMartingale ? TCU_A(MartingaleMode == 4 ? TCUC_WARN : TCUC_ACC) : TCU_A(TCUC_DIM);
   TCU_MGMFillRoundRect(TCU_MGM_W-168, 10, 132, 16, 4, modeBg);
   TCU_MGMText(TCU_MGM_W-162, 13, modeTag, modeFg, 7);
   TCU_MGMBtn("TCU_MGM_CLOSE", TCU_MGM_W-28, 8, 20, 20, "X", TCU_A(C'50,20,20'), TCU_A(TCUC_TXT), 8, 4);

   int x = 10, y = 44;
   if(g_mgmSelected >= 0 && g_mgmSelected < g_mgCount)
      TCU_DrawMGMonitorDetail(x, y);
   else
      TCU_DrawMGMonitorList(x, y);

   g_mgmCanvas.Update();
   ChartRedraw(0);
}

void TCU_ProcessMGMonitorClick(string hit)
{
   if(hit == "TCU_MGM_CLOSE") { g_mgmOpen = false; TCU_DestroyMGMonitor(); TCU_DrawUI(); return; }
   if(hit == "TCU_MGM_BACK")  { g_mgmSelected = -1; TCU_DrawMGMonitor(); return; }
   if(hit == "TCU_MGM_UP")    { if(g_mgmScroll > 0) g_mgmScroll--; TCU_DrawMGMonitor(); return; }
   if(hit == "TCU_MGM_DN")    { g_mgmScroll++; TCU_DrawMGMonitor(); return; }
   if(hit == "TCU_MGM_RESET_SYM")
   {
      if(g_mgmSelected >= 0 && g_mgmSelected < g_mgCount)
      {
         g_mgTable[g_mgmSelected].streak    = 0;
         g_mgTable[g_mgmSelected].mgPnl     = 0;
         g_mgTable[g_mgmSelected].wins      = 0;
         g_mgTable[g_mgmSelected].losses    = 0;
         g_mgTable[g_mgmSelected].lastPnl   = 0;
         g_mgTable[g_mgmSelected].carry     = 0;
         g_mgTable[g_mgmSelected].recTarget = 0;
      }
      TCU_DrawMGMonitor();
      return;
   }
   if(StringFind(hit, "TCU_MGM_ROW_") == 0)
   {
      int idx = (int)StringToInteger(StringSubstr(hit, 12));
      if(idx >= 0 && idx < g_mgCount) { g_mgmSelected = idx; TCU_DrawMGMonitor(); }
      return;
   }
}

// ============================================================
// [ADV] Advanced Settings floating popup
// ============================================================
void TCU_ADVRegHit(string name, int x, int y, int w, int h)
{
   ArrayResize(g_advHits, g_advHitCount + 1);
   g_advHits[g_advHitCount].name = name;
   g_advHits[g_advHitCount].x = x;
   g_advHits[g_advHitCount].y = y;
   g_advHits[g_advHitCount].w = w;
   g_advHits[g_advHitCount].h = h;
   g_advHitCount++;
}
string TCU_ADVHitTest(int mx, int my)
{
   for(int i = g_advHitCount - 1; i >= 0; i--)
      if(mx >= g_advHits[i].x && mx < g_advHits[i].x + g_advHits[i].w
         && my >= g_advHits[i].y && my < g_advHits[i].y + g_advHits[i].h)
         return g_advHits[i].name;
   return "";
}
void TCU_ADVFillRR(int x, int y, int w, int h, int r, uint clr)
{
   if(r <= 0) { g_advCanvas.FillRectangle(x, y, x+w-1, y+h-1, clr); return; }
   int x2=x+w-1, y2=y+h-1;
   g_advCanvas.FillRectangle(x+r,y,x2-r,y2,clr);
   g_advCanvas.FillRectangle(x,y+r,x+r-1,y2-r,clr);
   g_advCanvas.FillRectangle(x2-r+1,y+r,x2,y2-r,clr);
   g_advCanvas.FillCircle(x+r,y+r,r,clr); g_advCanvas.FillCircle(x2-r,y+r,r,clr);
   g_advCanvas.FillCircle(x+r,y2-r,r,clr); g_advCanvas.FillCircle(x2-r,y2-r,r,clr);
}
void TCU_ADVText(int x, int y, string txt, uint clr, int sz=8, string font="Segoe UI")
   { g_advCanvas.FontSet(font,-sz*10); g_advCanvas.TextOut(x,y,txt,clr); }
void TCU_ADVTextBold(int x, int y, string txt, uint clr, int sz=8)
   { TCU_ADVText(x,y,txt,clr,sz,"Segoe UI Semibold"); }
void TCU_ADVBtn(string name, int x, int y, int w, int h, string txt, uint bg, uint fg, int sz=7, int r=4)
{
   int off = (name==g_advPressed && name!="") ? 1 : 0;
   if(off>0) bg=TCU_Darken(bg,15);
   TCU_ADVFillRR(x,y+off,w,h,r,bg);
   g_advCanvas.FontSet("Segoe UI Semibold",-sz*10);
   int tw=0,th=0; g_advCanvas.TextSize(txt,tw,th);
   g_advCanvas.TextOut(x+(w-tw)/2,y+off+(h-th)/2,txt,fg);
   TCU_ADVRegHit(name,x,y,w,h);
}
void TCU_ADVValueRow(int x, int &y, string label, string keyDec, string keyInc, string valStr)
{
   TCU_ADVFillRR(x, y, TCU_ADV_W-20, 24, 4, TCU_A(TCUC_CARD));
   TCU_ADVText(x+8, y+7, label, TCU_A(TCUC_DIM), 7);
   int bx = x+148;
   TCU_ADVBtn(keyDec, bx, y+3, 22, 18, "-", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 9, 3);
   // Draw value box + text on canvas so value is always visible
   TCU_ADVFillRR(bx+26, y+3, 72, 18, 3, TCU_A(C'31,52,82'));
   g_advCanvas.FontSet("Segoe UI Semibold", -70);
   int _vtw=0, _vth=0; g_advCanvas.TextSize(valStr, _vtw, _vth);
   g_advCanvas.TextOut(bx+26+(72-_vtw)/2, y+3+(18-_vth)/2, valStr, TCU_A(TCUC_ACC));
   string editKey = StringSubstr(keyDec, 12);
   string name = TCUC_PFX+"ED_"+editKey;
   TCU_RegisterEdit(name);
   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_EDIT,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'31,52,82');
      ObjectSetInteger(0,name,OBJPROP_COLOR,TCUC_ACC);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,TCUC_GRID);
      ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_CENTER);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,7);
      ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI Semibold");
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,20);
   }
   TCU_PositionEdit(name, g_advX+bx+26, g_advY+y+3, 72, 18);
   TCU_SetEditText(name, valStr);
   TCU_ADVBtn(keyInc, bx+102, y+3, 22, 18, "+", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 9, 3);
   y += 27;
}
void TCU_DestroyAdvPopup()
{
   if(g_advCreated) { g_advCanvas.Destroy(); g_advCreated=false; }
   ObjectDelete(0, TCUC_PFX+"ADV_CV");
   g_advHitCount=0; ArrayResize(g_advHits,0);
}
void TCU_OpenAdvPopup()
{
   g_tcuAdvSetOpen = true;
   if(g_advX<0||g_advY<0)
   {
      int cW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
      int cH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
      g_advX = g_panelX+g_panelW+10;
      if(g_advX+TCU_ADV_W>cW-10) g_advX=MathMax(10,g_panelX-TCU_ADV_W-10);
      g_advY = g_panelY+50;
      if(g_advY+TCU_ADV_H>cH-10) g_advY=MathMax(10,cH-TCU_ADV_H-10);
   }
}
void TCU_DrawAdvPopup()
{
   if(!g_tcuAdvSetOpen) return;
   string name = TCUC_PFX+"ADV_CV";
   if(g_advCreated)
   {
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,g_advX);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,g_advY);
      g_advCanvas.Erase(0x00000000);
   }
   else
   {
      g_advCanvas.CreateBitmapLabel(0,0,name,g_advX,g_advY,TCU_ADV_W,TCU_ADV_H,COLOR_FORMAT_ARGB_NORMALIZE);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,7);
      g_advCanvas.Erase(0x00000000);
      g_advCreated=true;
   }
   g_advHitCount=0; ArrayResize(g_advHits,0);

   TCU_ADVFillRR(0,0,TCU_ADV_W,TCU_ADV_H,10,TCU_A(TCUC_BRD,250));
   TCU_ADVFillRR(1,1,TCU_ADV_W-2,TCU_ADV_H-2,9,TCU_A(TCUC_BG,248));
   TCU_ADVFillRR(1,1,TCU_ADV_W-2,36,9,TCU_A(TCUC_PNL,252));
   TCU_ADVTextBold(12,11,"ADVANCED SETTINGS",TCU_A(TCUC_TXT),9);
   TCU_ADVBtn("TCU_ADV_CLOSE",TCU_ADV_W-28,8,20,20,"X",TCU_A(C'50,20,20'),TCU_A(TCUC_TXT),8,4);

   int x=10, y=44;
   TCU_ADVTextBold(x+4, y, "RECOVERY (ADVANCED) MODE", TCU_A(TCUC_ACC), 7);
   y+=16;
   TCU_ADVText(x+4, y, "No settings -- it sizes each recovery from the", TCU_A(TCUC_DIM), 7);
   y+=13;
   TCU_ADVText(x+4, y, "carried loss + the signal's own TP profit.", TCU_A(TCUC_DIM), 7);
   y+=18;
   TCU_ADVFillRR(x, y, TCU_ADV_W-20, 1, 0, TCU_A(TCUC_GRID));
   y+=6;
   TCU_ADVTextBold(x+4, y, "RESET RULES", TCU_A(TCUC_ACC), 7);
   y+=18;
   TCU_ADVValueRow(x, y, "Max Steps (streak limit)", "TCU_ADJ_DEC_MG_MAXSTEPS", "TCU_ADJ_INC_MG_MAXSTEPS",
                   IntegerToString(MartingaleMaxSteps));
   TCU_ADVText(x+8, y+2, "Streak resets after N losses.", TCU_A(TCUC_WARN), 6);
   y+=14;
   TCU_ADVFillRR(x, y, TCU_ADV_W-20, 24, 4, TCU_A(TCUC_CARD));
   TCU_ADVText(x+8, y+7, "Reset on Win", TCU_A(TCUC_DIM), 7);
   TCU_ADVBtn("TCU_ADV_TOGGLE_RESETWIN", x+TCU_ADV_W-74, y+3, 54, 18,
              MartingaleResetOnWin ? "ON" : "OFF",
              TCU_A(MartingaleResetOnWin ? C'0,80,40' : C'60,20,20'), TCU_A(TCUC_TXT), 7, 4);
   y+=27;
   TCU_ADVText(x+8, y+2, "ON = winning trade resets streak to base lot.", TCU_A(TCUC_WARN), 6);
   y+=14;
   string _mlStr = (MartingaleMaxLoss<=0) ? "OFF" : "$"+DoubleToString(MartingaleMaxLoss,0);
   TCU_ADVValueRow(x, y, "Max Loss Cap ($)", "TCU_ADJ_DEC_MG_MAXLOSS", "TCU_ADJ_INC_MG_MAXLOSS", _mlStr);
   TCU_ADVText(x+8, y+2, "Stop MG sizing if cumulative loss hits this. 0=off.", TCU_A(TCUC_WARN), 6);
   y+=18;
   TCU_ADVText(x+4,y,"Drag to move.  Changes saved automatically.",TCU_A(TCUC_HINT),6);
   g_advCanvas.Update();
   ChartRedraw(0);
}
void TCU_ProcessAdvClick(string hit)
{
   if(hit=="TCU_ADV_CLOSE") { g_tcuAdvSetOpen=false; TCU_DestroyAdvPopup(); TCU_DrawUI(); return; }
   if(hit=="TCU_ADV_TOGGLE_RESETWIN") { MartingaleResetOnWin=!MartingaleResetOnWin; TCU_CommitSettings(); TCU_DrawAdvPopup(); TCU_DrawUI(); return; }
   int dir=0; string key="";
   if(StringFind(hit,"TCU_ADJ_INC_")==0) { dir=1;  key=StringSubstr(hit,12); }
   if(StringFind(hit,"TCU_ADJ_DEC_")==0) { dir=-1; key=StringSubstr(hit,12); }
   if(dir!=0 && key!="")
   {
      if(key=="MG_MAXSTEPS")      MartingaleMaxSteps = MathMax(1, MartingaleMaxSteps+dir);
      else if(key=="MG_MAXLOSS")  MartingaleMaxLoss  = MathMax(0.0, MartingaleMaxLoss+dir*50.0);
      TCU_CommitSettings();
      TCU_DrawAdvPopup();
      TCU_DrawUI();
   }
}

// ============================================================
// [PROF] Profiles floating popup
// ============================================================
void TCU_PROFRegHit(string name, int x, int y, int w, int h)
{
   ArrayResize(g_profHits, g_profHitCount + 1);
   g_profHits[g_profHitCount].name=name; g_profHits[g_profHitCount].x=x;
   g_profHits[g_profHitCount].y=y; g_profHits[g_profHitCount].w=w;
   g_profHits[g_profHitCount].h=h; g_profHitCount++;
}
string TCU_PROFHitTest(int mx, int my)
{
   for(int i=g_profHitCount-1;i>=0;i--)
      if(mx>=g_profHits[i].x&&mx<g_profHits[i].x+g_profHits[i].w
         &&my>=g_profHits[i].y&&my<g_profHits[i].y+g_profHits[i].h)
         return g_profHits[i].name;
   return "";
}
void TCU_PROFFillRR(int x,int y,int w,int h,int r,uint clr)
{
   if(r<=0){g_profCanvas.FillRectangle(x,y,x+w-1,y+h-1,clr);return;}
   int x2=x+w-1,y2=y+h-1;
   g_profCanvas.FillRectangle(x+r,y,x2-r,y2,clr);
   g_profCanvas.FillRectangle(x,y+r,x+r-1,y2-r,clr);
   g_profCanvas.FillRectangle(x2-r+1,y+r,x2,y2-r,clr);
   g_profCanvas.FillCircle(x+r,y+r,r,clr);g_profCanvas.FillCircle(x2-r,y+r,r,clr);
   g_profCanvas.FillCircle(x+r,y2-r,r,clr);g_profCanvas.FillCircle(x2-r,y2-r,r,clr);
}
void TCU_PROFText(int x,int y,string txt,uint clr,int sz=8,string font="Segoe UI")
   {g_profCanvas.FontSet(font,-sz*10);g_profCanvas.TextOut(x,y,txt,clr);}
void TCU_PROFTextBold(int x,int y,string txt,uint clr,int sz=8)
   {TCU_PROFText(x,y,txt,clr,sz,"Segoe UI Semibold");}
void TCU_PROFBtn(string name,int x,int y,int w,int h,string txt,uint bg,uint fg,int sz=7,int r=4)
{
   int off=(name==g_profPressed&&name!="")?1:0;
   if(off>0)bg=TCU_Darken(bg,15);
   TCU_PROFFillRR(x,y+off,w,h,r,bg);
   g_profCanvas.FontSet("Segoe UI Semibold",-sz*10);
   int tw=0,th=0;g_profCanvas.TextSize(txt,tw,th);
   g_profCanvas.TextOut(x+(w-tw)/2,y+off+(h-th)/2,txt,fg);
   TCU_PROFRegHit(name,x,y,w,h);
}
void TCU_DestroyProfilesPopup()
{
   if(g_profCreated){g_profCanvas.Destroy();g_profCreated=false;}
   ObjectDelete(0,TCUC_PFX+"PROF_CV");
   g_profHitCount=0; ArrayResize(g_profHits,0);
}
void TCU_OpenProfilesPopup()
{
   g_tcuProfileOpen=true;
   if(g_profX<0||g_profY<0)
   {
      int cW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
      int cH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
      g_profX=g_panelX+g_panelW+10;
      if(g_profX+TCU_PROF_W>cW-10) g_profX=MathMax(10,g_panelX-TCU_PROF_W-10);
      g_profY=g_panelY+g_panelH-TCU_PROF_H-10;
      if(g_profY<10) g_profY=MathMax(10,cH-TCU_PROF_H-10);
   }
}
void TCU_DrawProfilesPopup()
{
   if(!g_tcuProfileOpen) return;
   string name=TCUC_PFX+"PROF_CV";
   if(g_profCreated)
   {
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,g_profX);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,g_profY);
      g_profCanvas.Erase(0x00000000);
   }
   else
   {
      g_profCanvas.CreateBitmapLabel(0,0,name,g_profX,g_profY,TCU_PROF_W,TCU_PROF_H,COLOR_FORMAT_ARGB_NORMALIZE);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,7);
      g_profCanvas.Erase(0x00000000);
      g_profCreated=true;
   }
   g_profHitCount=0; ArrayResize(g_profHits,0);

   TCU_PROFFillRR(0,0,TCU_PROF_W,TCU_PROF_H,10,TCU_A(TCUC_BRD,250));
   TCU_PROFFillRR(1,1,TCU_PROF_W-2,TCU_PROF_H-2,9,TCU_A(TCUC_BG,248));
   TCU_PROFFillRR(1,1,TCU_PROF_W-2,36,9,TCU_A(TCUC_PNL,252));
   TCU_PROFTextBold(12,11,"PROFILES",TCU_A(TCUC_TXT),9);
   TCU_PROFBtn("TCU_PROF_CLOSE",TCU_PROF_W-28,8,20,20,"X",TCU_A(C'50,20,20'),TCU_A(TCUC_TXT),8,4);

   int x=10,y=44;
   // Profile name row
   TCU_PROFFillRR(x,y,TCU_PROF_W-20,24,4,TCU_A(TCUC_CARD));
   TCU_PROFText(x+8,y+7,"Profile Name",TCU_A(TCUC_DIM),7);
   string peName=TCUC_PFX+"ED_PROFNAME";
   TCU_RegisterEdit(peName);
   if(ObjectFind(0,peName)<0)
   {
      ObjectCreate(0,peName,OBJ_EDIT,0,0,0);
      ObjectSetInteger(0,peName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,peName,OBJPROP_BGCOLOR,C'31,52,82');
      ObjectSetInteger(0,peName,OBJPROP_COLOR,TCUC_ACC);
      ObjectSetInteger(0,peName,OBJPROP_BORDER_COLOR,TCUC_GRID);
      ObjectSetInteger(0,peName,OBJPROP_ALIGN,ALIGN_CENTER);
      ObjectSetInteger(0,peName,OBJPROP_FONTSIZE,7);
      ObjectSetString(0,peName,OBJPROP_FONT,"Segoe UI Semibold");
      ObjectSetInteger(0,peName,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,peName,OBJPROP_HIDDEN,false);
      ObjectSetInteger(0,peName,OBJPROP_BACK,false);
      ObjectSetInteger(0,peName,OBJPROP_ZORDER,20);
   }
   TCU_PositionEdit(peName,g_profX+x+96,g_profY+y+3,TCU_PROF_W-x-96-10,18);
   TCU_SetEditText(peName,g_tcuProfileName);
   y+=30;

   int bw=(TCU_PROF_W-26)/2;
   TCU_PROFBtn("TCU_PROF_SAVE",x,y,bw,30,"SAVE PROFILE",TCU_A(C'0,100,45'),TCU_A(TCUC_TXT),8,5);
   TCU_PROFBtn("TCU_PROF_LOAD",x+bw+6,y,bw,30,"LOAD PROFILE",TCU_A(C'31,52,82'),TCU_A(TCUC_TXT),8,5);
   y+=36;

   if(StringLen(g_tcuProfileStatus)>0 && GetTickCount64()-g_tcuProfileStatusAt<5000)
   {
      bool isErr=(StringFind(g_tcuProfileStatus,"ERROR")>=0||StringFind(g_tcuProfileStatus,"NOT FOUND")>=0);
      TCU_PROFFillRR(x,y,TCU_PROF_W-20,24,4,TCU_A(isErr?C'72,22,22':C'12,55,30'));
      TCU_PROFTextBold(x+8,y+6,TCU_Short(g_tcuProfileStatus,38),TCU_A(isErr?TCUC_DNG:TCUC_OK),7);
      y+=28;
   }
   TCU_PROFText(x+4,y,"Saves to MT5 Common/Files as TCU_Profile_<name>.cfg",TCU_A(TCUC_HINT),6);
   TCU_PROFText(x+4,y+14,"Drag title bar to move.",TCU_A(TCUC_HINT),6);
   g_profCanvas.Update();
   ChartRedraw(0);
}
void TCU_ProcessProfClick(string hit)
{
   if(hit=="TCU_PROF_CLOSE") {g_tcuProfileOpen=false;TCU_DestroyProfilesPopup();TCU_DrawUI();return;}
   if(hit=="TCU_PROF_SAVE")  {TCU_ExportProfile(g_tcuProfileName);TCU_DrawProfilesPopup();return;}
   if(hit=="TCU_PROF_LOAD")  {TCU_ImportProfile(g_tcuProfileName);TCU_CommitSettings();TCU_DrawProfilesPopup();TCU_DrawUI();return;}
}

void TCU_OpenMonitorPopup()
{
   g_tcuMonOpen = true;
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(g_tcuMonX < 0 || g_tcuMonY < 0)
   {
      g_tcuMonX = g_panelX + g_panelW + 10;
      if(g_tcuMonX + TCUO_W > chartW - 10)
         g_tcuMonX = MathMax(10, g_panelX - TCUO_W - 10);
      g_tcuMonY = g_panelY + 30;
      if(g_tcuMonY + TCUO_H > chartH - 10)
         g_tcuMonY = MathMax(10, chartH - TCUO_H - 10);
   }
}

void TCU_DrawMonitorPopup()
{
   if(!g_tcuMonOpen)
   {
      TCU_DestroyMonitorPopup();
      return;
   }

   string name = TCUC_PFX + "MON_CV";
   if(g_tcuMonCreated)
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_tcuMonX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_tcuMonY);
      g_tcuMonCanvas.Erase(0x00000000);
   }
   else
   {
      g_tcuMonCanvas.CreateBitmapLabel(0, 0, name, g_tcuMonX, g_tcuMonY, TCUO_W, TCUO_H, COLOR_FORMAT_ARGB_NORMALIZE);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 6);
      g_tcuMonCanvas.Erase(0x00000000);
      g_tcuMonCreated = true;
   }

   g_tcuMonHitCount = 0;
   ArrayResize(g_tcuMonHits, 0);

   TCU_MonFillRoundRect(0, 0, TCUO_W, TCUO_H, 10, TCU_A(TCUC_BRD, 250));
   TCU_MonFillRoundRect(1, 1, TCUO_W - 2, TCUO_H - 2, 9, TCU_A(TCUC_BG, 248));
   TCU_MonFillRoundRect(1, 1, TCUO_W - 2, 36, 9, TCU_A(TCUC_PNL, 252));
   TCU_MonTextBold(12, 11, "TRADE MONITOR", TCU_A(TCUC_TXT), 9);
   TCU_MonBtn("TCU_MON_TAB_TR", 126, 8, 82, 22, "Trades", TCU_A(g_tcuMonTab == 0 ? TCUC_ACC : TCUC_GRID), TCU_A(clrWhite), 7, 4);
   TCU_MonBtn("TCU_MON_TAB_OR", 212, 8, 82, 22, "Orders", TCU_A(g_tcuMonTab == 1 ? TCUC_ACC : TCUC_GRID), TCU_A(clrWhite), 7, 4);
   TCU_MonBtn("TCU_MON_CLOSE", TCUO_W - 28, 8, 16, 22, "X", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 4);

   ulong tickets[];
   bool  isOrderTab = (g_tcuMonTab == 1);
   int count = 0;
   if(!isOrderTab)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk <= 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
         ArrayResize(tickets, count + 1);
         tickets[count++] = tk;
      }
      if(g_tcuMonTradeScroll > MathMax(0, count - 6)) g_tcuMonTradeScroll = MathMax(0, count - 6);
   }
   else
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(OrderGetTicket(i))) continue;
         ulong tk = OrderGetTicket(i);
         if(tk <= 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
         ArrayResize(tickets, count + 1);
         tickets[count++] = tk;
      }
      if(g_tcuMonOrderScroll > MathMax(0, count - 6)) g_tcuMonOrderScroll = MathMax(0, count - 6);
   }

   int scroll = isOrderTab ? g_tcuMonOrderScroll : g_tcuMonTradeScroll;
   int x = 10;
   int y = 46;
   TCU_MonFillRoundRect(x, y, TCUO_W - 20, 24, 5, TCU_A(C'18,22,34', 250));
   TCU_MonTextBold(x + 10, y + 7, isOrderTab ? "PENDING / PLACED ORDERS" : "OPEN EA TRADES", TCU_A(TCUC_ACC), 7);
   y += 30;

   if(count == 0)
   {
      TCU_MonFillRoundRect(x, y, TCUO_W - 20, 64, 7, TCU_A(TCUC_CARD, 248));
      TCU_MonTextBold(x + 12, y + 15, isOrderTab ? "No active orders" : "No active trades", TCU_A(TCUC_TXT), 8);
      TCU_MonText(x + 12, y + 35, "This popup only shows tickets managed by this EA magic number.", TCU_A(TCUC_DIM), 7);
      y += 72;
   }
   else
   {
      int shown = 0;
      for(int i = scroll; i < count && shown < 6; i++)
      {
         ulong tk = tickets[i];
         bool selected = (g_tcuMonSelectedTicket == tk && g_tcuMonSelectedIsOrder == isOrderTab);
         int rowH = 46;
         TCU_MonFillRoundRect(x, y, TCUO_W - 20, rowH, 7, TCU_A(selected ? C'28,46,74' : TCUC_CARD, 248));
         if(!isOrderTab && PositionSelectByTicket(tk))
         {
            string sym = PositionGetString(POSITION_SYMBOL);
            string side = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
            double lots = PositionGetDouble(POSITION_VOLUME);
            double pnl = PositionGetDouble(POSITION_PROFIT);
            string src = TCU_MonitorSource(PositionGetString(POSITION_COMMENT));
            string flags = TCU_PositionFlagsText(tk);
            TCU_MonTextBold(x + 10, y + 7, sym + " • " + TCU_Short(src, 20), TCU_A(TCUC_TXT), 8);
            TCU_MonTextBold(x + 250, y + 7, side + " " + DoubleToString(lots, 2), TCU_A(side == "BUY" ? TCUC_OK : TCUC_DNG), 7);
            TCU_MonText(x + 10, y + 25, "PnL " + (pnl >= 0 ? "+" : "") + DoubleToString(pnl, 2), TCU_A(pnl >= 0 ? TCUC_OK : TCUC_DNG), 7);
            TCU_MonText(x + 118, y + 25, StringLen(flags) > 0 ? flags : "LIVE", TCU_A(TCUC_DIM), 7);
         }
         else if(isOrderTab && OrderSelect(tk))
         {
            string sym = OrderGetString(ORDER_SYMBOL);
            ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            string side = EnumToString(ot);
            double lots = OrderGetDouble(ORDER_VOLUME_CURRENT);
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            string src = TCU_MonitorSource(OrderGetString(ORDER_COMMENT));
            string flags = TCU_OrderFlagsText(tk);
            TCU_MonTextBold(x + 10, y + 7, sym + " • " + TCU_Short(src, 20), TCU_A(TCUC_TXT), 8);
            TCU_MonTextBold(x + 226, y + 7, TCU_Short(side, 14), TCU_A(TCUC_WARN), 7);
            TCU_MonText(x + 10, y + 25, "Lot " + DoubleToString(lots, 2) + " @ " + DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), TCU_A(TCUC_ACC), 7);
            TCU_MonText(x + 214, y + 25, StringLen(flags) > 0 ? flags : "PENDING", TCU_A(TCUC_DIM), 7);
         }
         TCU_MonRegHit("TCU_MON_ROW_" + TCU_TicketText(tk), x, y, TCUO_W - 20, rowH);
         y += rowH + 6;
         shown++;
      }

      bool canUp = (scroll > 0);
      bool canDown = (scroll + 6 < count);
      int firstRow = count > 0 ? (scroll + 1) : 0;
      int lastRow  = MathMin(count, scroll + shown);
      TCU_MonFillRoundRect(x, y + 2, TCUO_W - 20, 28, 6, TCU_A(C'18,22,34', 252));
      TCU_MonBtn("TCU_MON_UP", x + 88, y + 6, 52, 20, "^", TCU_A(canUp ? TCUC_GRID : C'18,22,34'), TCU_A(canUp ? TCUC_TXT : TCUC_DIM), 8, 4);
      TCU_MonBtn("TCU_MON_DOWN", x + 196, y + 6, 52, 20, "v", TCU_A(canDown ? TCUC_GRID : C'18,22,34'), TCU_A(canDown ? TCUC_TXT : TCUC_DIM), 8, 4);
      TCU_MonText(x + 146, y + 11, IntegerToString(firstRow) + "-" + IntegerToString(lastRow) + " / " + IntegerToString(count), TCU_A(TCUC_DIM), 7);
      y += 36;
   }

   if(g_tcuMonSelectedTicket == 0 && count > 0)
   {
      g_tcuMonSelectedTicket = tickets[scroll];
      g_tcuMonSelectedIsOrder = isOrderTab;
   }

   TCU_MonFillRoundRect(x, TCUO_H - 118, TCUO_W - 20, 104, 7, TCU_A(TCUC_CARD, 248));
   TCU_MonTextBold(x + 10, TCUO_H - 108, "DETAIL", TCU_A(TCUC_ACC), 7);
   if(g_tcuMonSelectedTicket > 0 && g_tcuMonSelectedIsOrder == isOrderTab)
   {
      if(!isOrderTab && PositionSelectByTicket(g_tcuMonSelectedTicket))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         TCU_MonText(x + 10, TCUO_H - 88, "Ticket: #" + TCU_TicketText(g_tcuMonSelectedTicket) + "  Source: " + TCU_Short(TCU_MonitorSource(PositionGetString(POSITION_COMMENT)), 20), TCU_A(TCUC_TXT), 7);
         TCU_MonText(x + 10, TCUO_H - 68, "Open: " + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), digits) + "  SL: " + DoubleToString(PositionGetDouble(POSITION_SL), digits), TCU_A(TCUC_DIM), 7);
         TCU_MonText(x + 10, TCUO_H - 48, "TP: " + DoubleToString(PositionGetDouble(POSITION_TP), digits) + "  Flags: " + TCU_Short(TCU_PositionFlagsText(g_tcuMonSelectedTicket), 18), TCU_A(TCUC_DIM), 7);
         TCU_MonText(x + 10, TCUO_H - 28, "Opened: " + TimeToString((datetime)PositionGetInteger(POSITION_TIME), TIME_DATE|TIME_MINUTES), TCU_A(TCUC_DIM), 7);
      }
      else if(isOrderTab && OrderSelect(g_tcuMonSelectedTicket))
      {
         string sym = OrderGetString(ORDER_SYMBOL);
         int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         TCU_MonText(x + 10, TCUO_H - 88, "Ticket: #" + TCU_TicketText(g_tcuMonSelectedTicket) + "  Source: " + TCU_Short(TCU_MonitorSource(OrderGetString(ORDER_COMMENT)), 20), TCU_A(TCUC_TXT), 7);
         TCU_MonText(x + 10, TCUO_H - 68, "Type: " + EnumToString((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)) + "  Lot: " + DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 2), TCU_A(TCUC_DIM), 7);
         TCU_MonText(x + 10, TCUO_H - 48, "Price: " + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), digits) + "  SL: " + DoubleToString(OrderGetDouble(ORDER_SL), digits), TCU_A(TCUC_DIM), 7);
         TCU_MonText(x + 10, TCUO_H - 28, "TP: " + DoubleToString(OrderGetDouble(ORDER_TP), digits) + "  Flags: " + TCU_Short(TCU_OrderFlagsText(g_tcuMonSelectedTicket), 18), TCU_A(TCUC_DIM), 7);
      }
      else
      {
         TCU_MonText(x + 10, TCUO_H - 78, "Selected ticket is no longer active.", TCU_A(TCUC_DIM), 7);
      }
   }
   else
   {
      TCU_MonText(x + 10, TCUO_H - 78, "Select a row to inspect source, price, SL/TP, and flags.", TCU_A(TCUC_DIM), 7);
   }

   g_tcuMonCanvas.Update(true);
}

void TCU_ProcessMonitorClick(string hit)
{
   if(hit == "") return;
   if(hit == "TCU_MON_CLOSE") { g_tcuMonOpen = false; TCU_DestroyMonitorPopup(); return; }
   if(hit == "TCU_MON_TAB_TR") { g_tcuMonTab = 0; g_tcuMonSelectedTicket = 0; g_tcuMonSelectedIsOrder = false; TCU_DrawMonitorPopup(); return; }
   if(hit == "TCU_MON_TAB_OR") { g_tcuMonTab = 1; g_tcuMonSelectedTicket = 0; g_tcuMonSelectedIsOrder = true; TCU_DrawMonitorPopup(); return; }
   if(hit == "TCU_MON_UP")
   {
      if(g_tcuMonTab == 0 && g_tcuMonTradeScroll > 0) g_tcuMonTradeScroll--;
      if(g_tcuMonTab == 1 && g_tcuMonOrderScroll > 0) g_tcuMonOrderScroll--;
      TCU_DrawMonitorPopup();
      return;
   }
   if(hit == "TCU_MON_DOWN")
   {
      if(g_tcuMonTab == 0) g_tcuMonTradeScroll++;
      else g_tcuMonOrderScroll++;
      TCU_DrawMonitorPopup();
      return;
   }
   if(StringFind(hit, "TCU_MON_ROW_") == 0)
   {
      g_tcuMonSelectedTicket = (ulong)StringToInteger(StringSubstr(hit, 12));
      g_tcuMonSelectedIsOrder = (g_tcuMonTab == 1);
      TCU_DrawMonitorPopup();
      return;
   }
}

// ===========================================================================
// [v6.00 NEW][PerSymUI] Per-Symbol Lots configurator -- data layer + modal popup
// ===========================================================================

// Round to broker volume step for `sym`. Falls back to 0.01 when broker data missing.
double Psl_NormalizeLot(string sym, double lot)
{
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   if(minL <= 0) minL = 0.01;
   if(maxL <= 0) maxL = 100.0;
   double clamped = MathMax(minL, MathMin(maxL, lot));
   double snapped = MathRound(clamped / step) * step;
   return NormalizeDouble(snapped, 2);
}

// Resolve a typed key against MarketWatch. Returns the broker-actual symbol name
// (e.g. "XAUUSD.m" when user typed "XAUUSD") or empty string if no match.
string Psl_ResolveKey(string key)
{
   if(StringLen(key) == 0) return "";
   if(SymbolInfoInteger(key, SYMBOL_SELECT) > 0) return key;
   string keyU = key; StringToUpper(keyU);
   int total = SymbolsTotal(true);
   for(int i = 0; i < total; i++)
   {
      string mw = SymbolName(i, true);
      string mwU = mw; StringToUpper(mwU);
      if(mwU == keyU) return mw;
      if(StringFind(mwU, keyU) == 0 && StringLen(mwU) > StringLen(keyU))
      {
         ushort nx = StringGetCharacter(mwU, StringLen(keyU));
         bool isLetter = (nx >= 'A' && nx <= 'Z') || (nx >= 'a' && nx <= 'z');
         if(!isLetter) return mw;
      }
   }
   return "";
}

// [v6.00 NEW][PerSymUI] Refresh g_pslResolved[] from current g_pslKeys[]. Walks
// MarketWatch once per entry. Called only after the entry array changes -- never
// from per-frame draw paths -- so panel/modal redraws are O(1) lookups.
void Psl_RefreshResolved()
{
   ArrayResize(g_pslResolved, g_pslCount);
   for(int i = 0; i < g_pslCount; i++)
      g_pslResolved[i] = g_tcuPslIsMGMode ? g_pslKeys[i] : Psl_ResolveKey(g_pslKeys[i]);
}

// Parse the global PerSymbolLots string into g_pslKeys / g_pslLots arrays.
// Idempotent: if the string hasn't changed since last parse, no-op.
void Psl_ParseFromString()
{
   string srcStr = g_tcuPslIsMGMode ? MGPerSymbolLots : PerSymbolLots;
   string lastSer = g_tcuPslIsMGMode ? g_mgpslLastSerialized : g_pslLastSerialized;
   bool modeChanged = (g_tcuPslIsMGMode != g_pslLastParseWasMG);
   if(!modeChanged && srcStr == lastSer) return;
   ArrayResize(g_pslKeys, 0);
   ArrayResize(g_pslLots, 0);
   g_pslCount = 0;
   if(StringLen(srcStr) > 0)
   {
      string entries[];
      int n = StringSplit(srcStr, ',', entries);
      for(int i = 0; i < n && g_pslCount < TCU_PERSYMBOL_MAX; i++)
      {
         string kv = entries[i];
         StringTrimLeft(kv); StringTrimRight(kv);
         if(StringLen(kv) == 0) continue;
         int eq = StringFind(kv, "=");
         if(eq <= 0) continue;
         string key = StringSubstr(kv, 0, eq);
         string val = StringSubstr(kv, eq + 1);
         StringTrimLeft(key); StringTrimRight(key);
         StringTrimLeft(val); StringTrimRight(val);
         if(StringLen(key) == 0) continue;
         double lot = StringToDouble(val);
         if(lot <= 0) continue;
         StringToUpper(key);
         // De-dupe: drop later occurrences of same key (first-match-wins matches GetPerSymbolLot).
         bool dup = false;
         for(int j = 0; j < g_pslCount; j++) { if(g_pslKeys[j] == key) { dup = true; break; } }
         if(dup) continue;
         ArrayResize(g_pslKeys, g_pslCount + 1);
         ArrayResize(g_pslLots, g_pslCount + 1);
         g_pslKeys[g_pslCount] = key;
         g_pslLots[g_pslCount] = lot;
         g_pslCount++;
      }
   }
   g_pslLastParseWasMG = g_tcuPslIsMGMode;
   if(g_tcuPslIsMGMode) g_mgpslLastSerialized = srcStr;
   else                  g_pslLastSerialized   = srcStr;
   Psl_RefreshResolved();
}

// Serialize arrays back into the global PerSymbolLots string and commit settings.
void Psl_SerializeToString()
{
   string s = "";
   for(int i = 0; i < g_pslCount; i++)
   {
      if(i > 0) s += ", ";
      s += g_pslKeys[i] + "=" + DoubleToString(g_pslLots[i], 2);
   }
   if(g_tcuPslIsMGMode) { MGPerSymbolLots = s; g_mgpslLastSerialized = s; }
   else                  { PerSymbolLots = s;   g_pslLastSerialized   = s; }
   TCU_CommitSettings();
}

// Add a new entry. Returns banner-style status text.
string Psl_AddEntry(string typedKey, double lot)
{
   Psl_ParseFromString();
   StringTrimLeft(typedKey); StringTrimRight(typedKey);
   if(StringLen(typedKey) == 0) return "Type a symbol name first";
   if(g_pslCount >= TCU_PERSYMBOL_MAX) return "Max " + IntegerToString(TCU_PERSYMBOL_MAX) + " entries reached";
   string keyU = typedKey; StringToUpper(keyU);
   for(int i = 0; i < g_pslCount; i++)
      if(g_pslKeys[i] == keyU) return "\"" + keyU + "\" already in list";
   string resolved = g_tcuPslIsMGMode ? typedKey : Psl_ResolveKey(typedKey);
   if(!g_tcuPslIsMGMode && StringLen(resolved) == 0)
      return "\"" + keyU + "\" not in MarketWatch";
   if(StringLen(resolved) == 0) resolved = keyU;
   double normLot = Psl_NormalizeLot(resolved, lot > 0 ? lot : 0.01);
   ArrayResize(g_pslKeys, g_pslCount + 1);
   ArrayResize(g_pslLots, g_pslCount + 1);
   g_pslKeys[g_pslCount] = keyU;
   g_pslLots[g_pslCount] = normLot;
   g_pslCount++;
   Psl_SerializeToString();
   Psl_RefreshResolved();
   return "Added " + keyU + " = " + DoubleToString(normLot, 2);
}

void Psl_RemoveEntry(int idx)
{
   if(idx < 0 || idx >= g_pslCount) return;
   for(int i = idx; i < g_pslCount - 1; i++)
   {
      g_pslKeys[i] = g_pslKeys[i + 1];
      g_pslLots[i] = g_pslLots[i + 1];
   }
   g_pslCount--;
   ArrayResize(g_pslKeys, g_pslCount);
   ArrayResize(g_pslLots, g_pslCount);
   Psl_SerializeToString();
   Psl_RefreshResolved();
}

void Psl_AdjustLot(int idx, int dir)
{
   if(idx < 0 || idx >= g_pslCount || dir == 0) return;
   string resolved = Psl_ResolveKey(g_pslKeys[idx]);
   string symForStep = (StringLen(resolved) > 0) ? resolved : _Symbol;
   double step = SymbolInfoDouble(symForStep, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   double next = g_pslLots[idx] + dir * step;
   g_pslLots[idx] = Psl_NormalizeLot(symForStep, next);
   Psl_SerializeToString();
}

void Psl_MoveEntry(int idx, int dir)
{
   if(dir == 0) return;
   int j = idx + dir;
   if(idx < 0 || idx >= g_pslCount || j < 0 || j >= g_pslCount) return;
   string tmpK = g_pslKeys[idx]; g_pslKeys[idx] = g_pslKeys[j]; g_pslKeys[j] = tmpK;
   double tmpL = g_pslLots[idx]; g_pslLots[idx] = g_pslLots[j]; g_pslLots[j] = tmpL;
   string tmpR = (ArraySize(g_pslResolved) > j) ? g_pslResolved[idx] : "";
   if(ArraySize(g_pslResolved) > j)
   {
      g_pslResolved[idx] = g_pslResolved[j];
      g_pslResolved[j] = tmpR;
   }
   Psl_SerializeToString();
}

// [v6.00 NEW][PerSymUI] Direct lot setter -- used by the row OBJ_EDIT (PSLLOT_<i>)
// when the user types a new value and presses Enter. Normalizes to the broker
// volume step like AdjustLot does. Returns true if value was changed.
bool Psl_SetLot(int idx, double lot)
{
   if(idx < 0 || idx >= g_pslCount) return false;
   if(lot <= 0) return false;
   string symForStep = (ArraySize(g_pslResolved) > idx && StringLen(g_pslResolved[idx]) > 0) ? g_pslResolved[idx] : _Symbol;
   double norm = Psl_NormalizeLot(symForStep, lot);
   if(MathAbs(norm - g_pslLots[idx]) < 1e-9) return false;
   g_pslLots[idx] = norm;
   Psl_SerializeToString();
   return true;
}

// ---------------------------------------------------------------------------
// Modal popup lifecycle + render
// ---------------------------------------------------------------------------
void TCU_DestroyPerSymPopup()
{
   if(g_tcuPslCreated)
   {
      g_tcuPslCanvas.Destroy();
      g_tcuPslCreated = false;
   }
   ObjectDelete(0, TCUC_PFX + "PSL_CV");
   ObjectDelete(0, TCUC_PFX + "ED_PSLADD");   // [v6.00 NEW][PerSymUI] in-modal Add input
   if(g_tcuActiveEdit == TCUC_PFX + "ED_PSLADD") g_tcuActiveEdit = "";
   // [v6.00 NEW][PerSymUI] Sweep all per-row lot edit boxes (PSLLOT_0 .. PSLLOT_<N-1>).
   for(int i = 0; i < TCU_PERSYMBOL_MAX; i++)
   {
      string n = TCUC_PFX + "ED_PSLLOT_" + IntegerToString(i);
      ObjectDelete(0, n);
      if(g_tcuActiveEdit == n) g_tcuActiveEdit = "";
   }
   g_tcuPslHitCount = 0;
   ArrayResize(g_tcuPslHits, 0);
}

void TCU_OpenPerSymPopup()
{
   Psl_ParseFromString();
   g_tcuPslOpen = true;
   g_tcuPslScroll = 0;
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(g_tcuPslX < 0 || g_tcuPslY < 0)
   {
      g_tcuPslX = g_panelX + g_panelW + 10;
      if(g_tcuPslX + TCU_PSL_W > chartW - 10)
         g_tcuPslX = MathMax(10, g_panelX - TCU_PSL_W - 10);
      g_tcuPslY = g_panelY + 30;
      if(g_tcuPslY + TCU_PSL_H > chartH - 10)
         g_tcuPslY = MathMax(10, chartH - TCU_PSL_H - 10);
   }
}

#define TCU_PSL_ROW_H   30
#define TCU_PSL_VISIBLE 7

void TCU_DrawPerSymPopup()
{
   if(!g_tcuPslOpen)
   {
      TCU_DestroyPerSymPopup();
      return;
   }
   Psl_ParseFromString();

   string name = TCUC_PFX + "PSL_CV";
   if(g_tcuPslCreated)
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_tcuPslX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_tcuPslY);
      g_tcuPslCanvas.Erase(0x00000000);
   }
   else
   {
      g_tcuPslCanvas.CreateBitmapLabel(0, 0, name, g_tcuPslX, g_tcuPslY, TCU_PSL_W, TCU_PSL_H, COLOR_FORMAT_ARGB_NORMALIZE);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 8);
      g_tcuPslCanvas.Erase(0x00000000);
      g_tcuPslCreated = true;
   }

   g_tcuPslHitCount = 0;
   ArrayResize(g_tcuPslHits, 0);

   // Backdrop
   TCU_PslFillRoundRect(0, 0, TCU_PSL_W, TCU_PSL_H, 10, TCU_A(TCUC_BRD, 250));
   TCU_PslFillRoundRect(1, 1, TCU_PSL_W - 2, TCU_PSL_H - 2, 9, TCU_A(TCUC_BG, 248));
   // Title bar (drag handle)
   TCU_PslFillRoundRect(1, 1, TCU_PSL_W - 2, 36, 9, TCU_A(TCUC_PNL, 252));
   TCU_PslTextBold(12, 11, g_tcuPslIsMGMode ? "MG PER-SYMBOL BASE LOTS" : "PER-SYMBOL LOT OVERRIDES", TCU_A(TCUC_TXT), 9);
   TCU_PslBtn("TCU_PSL_CLOSE", TCU_PSL_W - 28, 8, 16, 22, "X", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 4);

   int x = 10;
   int y = 44;
   // [v6.00 NEW][PerSymUI] Help lines bumped from sz=7 to sz=8 + Semibold for legibility.
   TCU_PslTextBold(x, y, g_tcuPslIsMGMode ? "Per-symbol base lot for each martingale series." : "Symbols not in this list use Global Lot Mode.", TCU_A(TCUC_TXT), 8);
   y += 16;
   TCU_PslText(x, y, g_tcuPslIsMGMode ? "Max " + IntegerToString(TCU_PERSYMBOL_MAX) + " entries. Order = match priority." : "Max " + IntegerToString(TCU_PERSYMBOL_MAX) + " entries. MarketWatch only. Order = match priority.", TCU_A(TCUC_DIM), 8);
   y += 20;

   // [v6.00 NEW][PerSymUI] In-modal Add row: type symbol -> click Add. Resolves
   // against MarketWatch, defaults to 0.01 lot, banner reports success / typo.
   {
      int rowW = TCU_PSL_W - 20;
      TCU_PslFillRoundRect(x, y, rowW, 28, 5, TCU_A(TCUC_CARD, 248));
      TCU_PslTextBold(x + 10, y + 9, "Add symbol", TCU_A(TCUC_TXT), 8);
      TCU_PslEditBox("PSLADD", x + 110, y + 5, 150, 18, g_tcuPslAddInputCache);
      TCU_PslBtn("TCU_PSL_ADD", x + 270, y + 5, 90, 18, "Add", TCU_A(TCUC_ACC), TCU_A(clrWhite), 8, 4);
      y += 32;
   }
   // Transient banner (auto-clears after 5s on next redraw)
   if(StringLen(g_tcuPslAddBanner) > 0)
   {
      ulong now = GetTickCount64();
      if(now - g_tcuPslAddBannerAt > 5000) { g_tcuPslAddBanner = ""; }
      else
      {
         bool isErr = (StringFind(g_tcuPslAddBanner, "not in") >= 0
                    || StringFind(g_tcuPslAddBanner, "already")  >= 0
                    || StringFind(g_tcuPslAddBanner, "Max ")     >= 0
                    || StringFind(g_tcuPslAddBanner, "Type ")    >= 0);
         uint bannerColor = isErr ? TCU_A(TCUC_WARN) : TCU_A(TCUC_OK);
         TCU_PslText(x + 4, y, g_tcuPslAddBanner, bannerColor, 7);
         y += 14;
      }
   }

   // List frame
   int listH = TCU_PSL_VISIBLE * TCU_PSL_ROW_H + 8;
   TCU_PslFillRoundRect(x, y, TCU_PSL_W - 20, listH, 6, TCU_A(C'18,22,34', 250));
   int listTop = y + 4;
   y += 4;

   if(g_pslCount == 0)
   {
      TCU_PslText(x + 12, y + 14, "No per-symbol overrides yet.", TCU_A(TCUC_DIM), 8);
      TCU_PslText(x + 12, y + 30, "Type a symbol above and click Add.", TCU_A(TCUC_DIM), 7);
      y = listTop + listH + 6;
   }
   else
   {
      int maxScroll = MathMax(0, g_pslCount - TCU_PSL_VISIBLE);
      if(g_tcuPslScroll > maxScroll) g_tcuPslScroll = maxScroll;
      if(g_tcuPslScroll < 0) g_tcuPslScroll = 0;
      int shown = 0;
      for(int i = g_tcuPslScroll; i < g_pslCount && shown < TCU_PSL_VISIBLE; i++, shown++)
      {
         int rowY = listTop + shown * TCU_PSL_ROW_H;
         TCU_PslFillRoundRect(x + 4, rowY + 2, TCU_PSL_W - 28, TCU_PSL_ROW_H - 4, 4, TCU_A(TCUC_CARD, 248));

         int cx = x + 8;
         // Up / Down reorder
         bool canUp   = (i > 0);
         bool canDown = (i < g_pslCount - 1);
         TCU_PslBtn("TCU_PSL_UP_" + IntegerToString(i),   cx,      rowY + 5, 18, 18, "^", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 3, canUp);
         TCU_PslBtn("TCU_PSL_DN_" + IntegerToString(i),   cx + 22, rowY + 5, 18, 18, "v", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 3, canDown);
         cx += 48;

         // Symbol label -- show resolved (broker-actual) name in parens if different from typed.
         // [v6.00 NEW][PerSymUI] Reads cached g_pslResolved[i] -- avoids re-iterating MarketWatch every frame.
         string resolved = (ArraySize(g_pslResolved) > i) ? g_pslResolved[i] : "";
         string keyDisp  = g_pslKeys[i];
         if(StringLen(resolved) > 0 && resolved != g_pslKeys[i])
            keyDisp = g_pslKeys[i] + " (" + resolved + ")";
         uint symColor = (StringLen(resolved) > 0) ? TCU_A(TCUC_TXT) : TCU_A(TCUC_DNG);
         TCU_PslTextBold(cx, rowY + 8, TCU_Short(keyDisp, 18), symColor, 8);
         cx += 142;

         // [v6.00 NEW][PerSymUI] [-]  [editable lot]  [+]
         // Lot value is now an OBJ_EDIT (PSLLOT_<i>) so users can type directly.
         // Press Enter to commit; the value is normalized to the broker's volume step.
         TCU_PslBtn("TCU_PSL_DEC_" + IntegerToString(i), cx,      rowY + 5, 18, 18, "-", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 9, 3);
         TCU_PslEditBox("PSLLOT_" + IntegerToString(i), cx + 22, rowY + 5, 50, 18, DoubleToString(g_pslLots[i], 2));
         TCU_PslBtn("TCU_PSL_INC_" + IntegerToString(i), cx + 76, rowY + 5, 18, 18, "+", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 9, 3);
         cx += 100;

         // Remove [x]
         TCU_PslBtn("TCU_PSL_RM_" + IntegerToString(i), cx, rowY + 5, 22, 18, "X", TCU_A(C'72,30,40'), TCU_A(TCUC_TXT), 8, 3);
      }
      // Scroll indicators
      bool needsUp   = g_tcuPslScroll > 0;
      bool needsDown = g_pslCount - g_tcuPslScroll > TCU_PSL_VISIBLE;
      TCU_PslBtn("TCU_PSL_SCRUP",  TCU_PSL_W - 24, listTop,                       16, 16, "^", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 3, needsUp);
      TCU_PslBtn("TCU_PSL_SCRDN",  TCU_PSL_W - 24, listTop + listH - 22,          16, 16, "v", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 8, 3, needsDown);
      y = listTop + listH + 6;
   }

   // [v6.00 NEW][PerSymUI] Footer count + global-lot note (sz=8 + Semibold for legibility).
   string countLine = IntegerToString(g_pslCount) + " / " + IntegerToString(TCU_PERSYMBOL_MAX) + " active overrides";
   TCU_PslTextBold(x, y, countLine, TCU_A(TCUC_TXT), 8);
   y += 16;
   TCU_PslText(x, y, g_tcuPslIsMGMode ? "Other symbols use the global Base Lot setting." : "Other symbols use Global Lot Mode (" + TCU_LotModeText() + ").", TCU_A(TCUC_DIM), 8);
   y += 22;
   // [v6.00 NEW][PerSymUI] Edits auto-persist; this is just a Close action (DeepSeek nit).
   TCU_PslBtn("TCU_PSL_SAVE", x, y, TCU_PSL_W - 20, 28, "Close", TCU_A(TCUC_ACC), TCU_A(clrWhite), 9, 5);

   g_tcuPslCanvas.Update(true);
}

void TCU_ProcessPerSymClick(string hit)
{
   if(hit == "") return;
   // [v6.00 NEW][PerSymUI] Flush any in-flight OBJ_EDIT (e.g. PSLADD) so we read
   // the freshest value the user typed before they clicked any modal button.
   TCU_FlushActiveEdit();
   if(hit == "TCU_PSL_CLOSE" || hit == "TCU_PSL_SAVE")
   {
      bool wasMG = g_tcuPslIsMGMode;
      g_tcuPslIsMGMode = false;
      if(wasMG) g_pslLastSerialized = ""; // force Lots-tab re-parse after MG popup
      g_tcuPslOpen = false;
      TCU_DestroyPerSymPopup();
      TCU_DrawUI();
      return;
   }
   // [v6.00 NEW][PerSymUI] In-modal Add button. Reads the symbol typed in the modal's
   // PSLADD edit box (TCU_PslEditBox) and routes through Psl_AddEntry. Same as the
   // panel-side Add button on the Lots tab; both paths share state via g_tcuPslAddInputCache.
   if(hit == "TCU_PSL_ADD")
   {
      string addName = TCUC_PFX + "ED_PSLADD";
      string typed = (ObjectFind(0, addName) >= 0) ? ObjectGetString(0, addName, OBJPROP_TEXT) : g_tcuPslAddInputCache;
      string status = Psl_AddEntry(typed, 0.01);
      g_tcuPslAddBanner   = status;
      g_tcuPslAddBannerAt = GetTickCount64();
      bool added = (StringFind(status, "Added ") == 0);
      if(added)
      {
         g_tcuPslAddInputCache = "";
         if(ObjectFind(0, addName) >= 0) ObjectSetString(0, addName, OBJPROP_TEXT, "");
      }
      TCU_DrawPerSymPopup();
      TCU_DrawUI();
      return;
   }
   if(hit == "TCU_PSL_SCRUP")  { if(g_tcuPslScroll > 0) g_tcuPslScroll--; TCU_DrawPerSymPopup(); return; }
   if(hit == "TCU_PSL_SCRDN")  { g_tcuPslScroll++; TCU_DrawPerSymPopup(); return; }
   if(StringFind(hit, "TCU_PSL_UP_")  == 0) { Psl_MoveEntry((int)StringToInteger(StringSubstr(hit, 11)), -1); TCU_DrawPerSymPopup(); TCU_DrawUI(); return; }
   if(StringFind(hit, "TCU_PSL_DN_")  == 0) { Psl_MoveEntry((int)StringToInteger(StringSubstr(hit, 11)),  1); TCU_DrawPerSymPopup(); TCU_DrawUI(); return; }
   if(StringFind(hit, "TCU_PSL_INC_") == 0) { Psl_AdjustLot((int)StringToInteger(StringSubstr(hit, 12)),  1); TCU_DrawPerSymPopup(); TCU_DrawUI(); return; }
   if(StringFind(hit, "TCU_PSL_DEC_") == 0) { Psl_AdjustLot((int)StringToInteger(StringSubstr(hit, 12)), -1); TCU_DrawPerSymPopup(); TCU_DrawUI(); return; }
   if(StringFind(hit, "TCU_PSL_RM_")  == 0) { Psl_RemoveEntry((int)StringToInteger(StringSubstr(hit, 11)));  TCU_DrawPerSymPopup(); TCU_DrawUI(); return; }
}

void TCU_DrawMini()
{
   TCU_InitCanvas(TCUC_MINI_W, TCUC_MINI_H);
   TCU_ResetVisibleEdits();
   g_panelW = TCUC_MINI_W;
   g_panelH = TCUC_MINI_H;
   TCU_FillRoundRectAA(0, 0, TCUC_MINI_W, TCUC_MINI_H, 8, TCU_A(TCUC_BRD));
   TCU_FillRoundRectAA(1, 1, TCUC_MINI_W - 2, TCUC_MINI_H - 2, 7, TCU_A(TCUC_PNL));
   TCU_TextBold(14, 10, "TRADE COPIER ULTIMATE", TCU_A(TCUC_TXT), 9);
   TCU_Text(16, 30, TCU_StatusText() + " | " + g_currentMode + " | Copied " + IntegerToString(g_tradesReceived), TCU_A(TCUC_DIM), 7);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   TCU_TextBold(220, 12, "$" + DoubleToString(eq, 2), TCU_A(eq >= bal ? TCUC_OK : TCUC_DNG), 8);
   TCU_Btn("TCU_MAX", TCUC_MINI_W - 32, 8, 20, 22, "+", TCU_A(TCUC_GRID), TCU_A(TCUC_TXT), 9, 4);
   TCU_HideStaleEdits();
   g_tcuCanvas.Update(true);
   if(g_tcuMonOpen) TCU_DrawMonitorPopup();
   if(g_tcuPslOpen) TCU_DrawPerSymPopup();   // [v6.00 NEW][PerSymUI]
   if(g_mgmOpen) TCU_DrawMGMonitor();
}

void TCU_DrawUI()
{
   if(g_tcuClosed)
   {
      TCU_DestroyCanvas();
      return;
   }
   UpdateModeStr();
   if(g_minimized)
   {
      TCU_DrawMini();
      return;
   }

   TCU_InitCanvas(TCUC_W, TCUC_H);
   g_panelW = TCUC_W;
   g_panelH = TCUC_H;
   TCU_ResetVisibleEdits();
   TCU_DrawHeader();

   switch(g_tcuTab)
   {
      case 0:  TCU_DrawSignalsTab();     break;
      case 13: TCU_DrawMartingaleTab();  break;
      default: TCU_DrawSystemTab();      break;
   }

   TCU_DrawFooter();
   // [v6.00 NEW][PerSymUI] Render modals BEFORE HideStaleEdits so the edits they
   // own (PSLADD + per-row PSLLOT_<i>) are registered for this frame and don't
   // get parked off-screen.
   if(g_tcuMonOpen) TCU_DrawMonitorPopup();
   if(g_tcuPslOpen) TCU_DrawPerSymPopup();
   if(g_mgmOpen) TCU_DrawMGMonitor();
   if(g_tcuAdvSetOpen) TCU_DrawAdvPopup();
   if(g_tcuProfileOpen) TCU_DrawProfilesPopup();
   TCU_HideStaleEdits();
   g_tcuCanvas.Update(true);
}

void TCU_MovePanel(int newX, int newY)
{
   int dx = newX - g_panelX;
   int dy = newY - g_panelY;
   if(dx == 0 && dy == 0) return;

   g_panelX = newX;
   g_panelY = newY;

   int total = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, TCUC_PFX) != 0) continue;
      int ox = (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE);
      int oy = (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, ox + dx);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, oy + dy);
   }

   string key = "TCU_" + IntegerToString((int)ChartID()) + "_";
   GlobalVariableSet(key + "PX", g_panelX);
   GlobalVariableSet(key + "PY", g_panelY);

   static ulong lastMoveDraw = 0;
   ulong now = GetMicrosecondCount() / 1000;
   if(now - lastMoveDraw >= 16)
   {
      lastMoveDraw = now;
      ChartRedraw();
   }
}

void TCU_ShowSettings()
{
   if(g_scOpen) _ScDeleteAll();
   else
   {
      g_scX = g_panelX + g_panelW + 10;
      g_scY = g_panelY;
      ShowScPanel();
   }
}

void TCU_CommitSettings()
{
   g_tcuSettingsDirty = true;
   g_tcuSettingsDirtyAt = GetTickCount64();
   TCU_DrawUI();
}

void TCU_FlushActiveEdit()
{
   if(StringLen(g_tcuActiveEdit) == 0) return;
   string name = g_tcuActiveEdit;
   g_tcuActiveEdit = "";
   if(ObjectFind(0, name) < 0) return;
   string pfx = TCUC_PFX + "ED_";
   if(StringFind(name, pfx) != 0) return;
   string key = StringSubstr(name, StringLen(pfx));
   string val = ObjectGetString(0, name, OBJPROP_TEXT);
   if(val == g_tcuActiveEditStart)
   {
      g_tcuActiveEditStart = "";
      return;
   }
   g_tcuActiveEditStart = "";
   TCU_ApplyEditValue(key, val);
}

double TCU_ClampDouble(double v, double lo, double hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

void TCU_AdjustSetting(string key, int dir)
{
   if(dir == 0) return;
   if(key == "FIXEDLOT")
      FixedLotSize = NormalizeDouble(TCU_ClampDouble(FixedLotSize + dir * 0.01, 0.01, MaxLotSize), 2);
   else if(key == "RISK")
      RiskPercent = NormalizeDouble(TCU_ClampDouble(RiskPercent + dir * 0.10, 0.10, 100.0), 2);
   else if(key == "DEFSL")
      DefaultSLPoints = MathMax(0, DefaultSLPoints + dir * 50);
   else if(key == "MAXLOT")
      MaxLotSize = NormalizeDouble(TCU_ClampDouble(MaxLotSize + dir * 0.10, 0.01, 1000.0), 2);
   else if(key == "MG_MULT")
      MartingaleMultiplier = NormalizeDouble(TCU_ClampDouble(MartingaleMultiplier + dir * 0.1, 1.1, 100.0), 2);
   else if(key == "MG_STEP")
      MartingaleFixedStep = NormalizeDouble(TCU_ClampDouble(MartingaleFixedStep + dir * 0.01, 0.01, 100.0), 2);
   else if(key == "MG_BASELOT")
      MartingaleBaseLot = NormalizeDouble(TCU_ClampDouble(MartingaleBaseLot + dir * 0.01, 0.01, 100.0), 2);
   else if(key == "MG_MAXSTEPS")
      MartingaleMaxSteps = MathMax(1, MartingaleMaxSteps + dir * 1);
   else if(key == "MG_MAXLOSS")
      MartingaleMaxLoss = MathMax(0.0, MartingaleMaxLoss + dir * 50.0);
   else
      return;

   if(FixedLotSize > MaxLotSize)
      FixedLotSize = MaxLotSize;
   TCU_CommitSettings();
   TCU_DrawUI();
}

void TCU_RunConnectionTest()
{
   if(!EnableBotAPIMode && !EnableBridgeMode)
   {
      Alert("[TCU] No active mode to test!\nEnable Bot API Mode or Bridge Mode first.");
      return;
   }

   if(EnableBotAPIMode)
   {
      // Ping Telegram Bot API -- getMe validates token without side effects
      if(StringLen(TelegramBotToken) == 0)
      {
         Alert("[TCU] Bot API mode is ON but no Token is set!");
         return;
      }
      string url = TELEGRAM_URL + TelegramBotToken + "/getMe";
      char post[], result[];
      string headers = "";
      string respHdr = "";
      ResetLastError();
      int res = WebRequest("GET", url, headers, 3000, post, result, respHdr);
      string resp = CharArrayToString(result);
      if(res == 200 && StringFind(resp, "\"ok\"") >= 0 && StringFind(resp, "true") >= 0)
      {
         Print("[TEST] Telegram Bot API: OK -- token valid and reachable.");
         g_lastError = "";
         Alert("[OK] Telegram Bot API: CONNECTED!\nToken is valid and bot is reachable.");
      }
      else if(res == -1)
      {
         int err = GetLastError();
         Print("[TEST] Telegram Bot API: BLOCKED (err=", err, ") -- add https://api.telegram.org to MT5 WebRequest URLs.");
         g_lastError = "TEST: Telegram WebRequest blocked";
         Alert("[FAIL] Telegram Bot API: BLOCKED!\nGo to: Tools > Options > Expert Advisors > Allow WebRequest\nAdd: https://api.telegram.org");
      }
      else
      {
         Print("[TEST] Telegram Bot API: FAILED HTTP=", res, " -- check Bot Token.");
         g_lastError = "TEST: Telegram HTTP " + IntegerToString(res);
         Alert("[FAIL] Telegram Bot API: FAILED (HTTP " + IntegerToString(res) + ")\nCheck your Bot Token is correct.");
      }
      TCU_DrawUI();
      return;
   }

   if(EnableBridgeMode)
   {
      // Early-exit if bridge is already known offline -- avoids blocking WebRequest freeze.
      // g_bridgeFailCount resets to 0 only when PollBridge succeeds, so this is reliable.
      ulong now = GetTickCount64();
      if(g_bridgeFailCount > 0 && now < g_bridgeNextRetry)
      {
         Print("[TEST] Bridge: OFFLINE (already in backoff) on port ", BridgePort);
         g_lastError = "TEST: Bridge offline :" + IntegerToString(BridgePort);
         TCU_DrawUI();
         Alert("[FAIL] Bridge: OFFLINE on port " + IntegerToString(BridgePort) + "\nMake sure the Bridge app is running.");
         return;
      }
      // Bridge state uncertain -- do a live probe with short timeout (local 127.0.0.1)
      string url = "http://127.0.0.1:" + IntegerToString(BridgePort) + "/signals/copier";
      char post[], result[];
      string headers = "X-NTS-Auth: " + NTS_AuthToken() + "\r\n"
                     + "X-Client-Id: " + NTS_ClientId() + "\r\n";
      string respHdr = "";
      ResetLastError();
      int res = WebRequest("GET", url, headers, 1000, post, result, respHdr);
      if(res == 200)
      {
         Print("[TEST] Bridge: CONNECTED on port ", BridgePort);
         g_lastError = "";
         g_bridgeFailCount = 0;
         TCU_DrawUI();
         Alert("[OK] Bridge: CONNECTED on port " + IntegerToString(BridgePort) + "!\nBridge app is running and reachable.");
      }
      else if(res == -1)
      {
         int err = GetLastError();
         Print("[TEST] Bridge: WebRequest BLOCKED (err=", err, ") -- add http://127.0.0.1 to MT5 WebRequest URLs.");
         g_lastError = "TEST: Bridge WebRequest blocked";
         TCU_DrawUI();
         Alert("[FAIL] Bridge: BLOCKED!\nGo to: Tools > Options > Expert Advisors > Allow WebRequest\nAdd: http://127.0.0.1");
      }
      else
      {
         Print("[TEST] Bridge: OFFLINE on port ", BridgePort, " (HTTP=", res, ")");
         g_lastError = "TEST: Bridge offline :" + IntegerToString(BridgePort);
         TCU_DrawUI();
         Alert("[FAIL] Bridge: OFFLINE on port " + IntegerToString(BridgePort) + "\nMake sure the Bridge app is running.");
      }
   }
}

void TCU_ApplyEditValue(string key, string val)
{
   StringTrimLeft(val);
   StringTrimRight(val);
   if(key == "TGPOLL") TelegramPollSeconds = MathMax(1, (int)StringToInteger(val));
   else if(key == "TGTOKEN") TelegramBotToken = val;
   else if(key == "TGCHAT") TelegramChatID = val;
   else if(key == "BRPORT") BridgePort = MathMax(1, (int)StringToInteger(val));
   else if(key == "BRPOLL") BridgePollMs = MathMax(200, (int)StringToInteger(val));
   else if(key == "DCWEBHOOK") DiscordWebhookURL = val;
   else if(key == "DCPOLL") DiscordPollSeconds = MathMax(1, (int)StringToInteger(val));
   else if(key == "COPIERFILE") CopierFileName = val;
   else if(key == "COPIERPOLL") CopierPollMs = MathMax(20, (int)StringToInteger(val));
   else if(key == "COPIERFIXED") CopierFixedLot = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, CopierMaxLot), 2);
   else if(key == "COPIERMULT") CopierLotMultiplier = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, 100.0), 2);
   else if(key == "COPIERRISK") CopierRiskPercent = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, 100.0), 2);
   else if(key == "COPIERMAX") CopierMaxLot = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, 1000.0), 2);
   else if(key == "COPIERMINLOT") CopierMinimumLotToCopy = NormalizeDouble(MathMax(0.0, StringToDouble(val)), 2);
   else if(key == "COPIERCOMMENT") CopierCustomTradeComment = val;
   else if(key == "FIXEDLOT") FixedLotSize = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, MaxLotSize), 2);
   else if(key == "RISK") RiskPercent = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, 100.0), 2);
   else if(key == "PSLADD") {  // [v6.00 NEW][PerSymUI] Cache "Add symbol" input so it survives redraws.
      g_tcuPslAddInputCache = val;
   }
   else if(StringFind(key, "PSLLOT_") == 0) {  // [v6.00 NEW][PerSymUI] Direct lot edit from modal row.
      int idx = (int)StringToInteger(StringSubstr(key, 7));
      double parsed = StringToDouble(val);
      Psl_SetLot(idx, parsed);
      if(g_tcuPslOpen) TCU_DrawPerSymPopup();
   }
   else if(key == "DEFSL") DefaultSLPoints = MathMax(0, (int)StringToInteger(val));
   else if(key == "MAXLOT") MaxLotSize = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, 1000.0), 2);
   else if(key == "MAXOPENPOS") MaxOpenPositions = MathMax(0, (int)StringToInteger(val));
   else if(key == "MAXTRADESMIN") MaxTradesPerMinute = MathMax(0, (int)StringToInteger(val));
   else if(key == "DAILYLOSSPCT") MaxDailyLossPercent = MathMax(0.0, StringToDouble(val));
   else if(key == "DAILYLOSSAMT") MaxDailyLossAmount = MathMax(0.0, StringToDouble(val));
   else if(key == "MAXSPREAD") MaxSpreadPoints = MathMax(0, (int)StringToInteger(val));
   else if(key == "SLIPPTS") SlippagePoints = MathMax(0, (int)StringToInteger(val));
   else if(key == "ENTRYSLIP") EntrySlippagePips = MathMax(0.0, StringToDouble(val));
   else if(key == "WHITELIST") WhitelistSymbols = val;
   else if(key == "BLACKLIST") BlacklistSymbols = val;
   else if(key == "SKIPKW") SkipKeywords = val;
   else if(key == "CUSTOMMAP") CustomMappings = val;
   else if(key == "KWREPLACE") KeywordReplaceMap = val;
   else if(key == "MOVESLCMD") MoveSLCommands = val;
   else if(key == "CLOSEALLCMD") CloseAllCommands = val;
   else if(key == "TIMESTART") TimeFilterStartHour = (int)TCU_ClampDouble((double)StringToInteger(val), 0, 23);
   else if(key == "TIMEEND") TimeFilterEndHour = (int)TCU_ClampDouble((double)StringToInteger(val), 0, 23);
   else if(key == "PEXPHOURS") PendingExpiryHours = MathMax(1, (int)StringToInteger(val));
   else if(key == "COOLDOWN") SignalCooldownSeconds = MathMax(0, (int)StringToInteger(val)) * 60;
   else if(key == "DUPWIN") DuplicateWindowMinutes = MathMax(1, (int)StringToInteger(val));
   else if(key == "MINPIPSDIST") MinPipsDistanceSameType = MathMax(0.0, StringToDouble(val));
   else if(key == "FALLSL") FallbackSLPips = MathMax(0, (int)StringToInteger(val));
   else if(key == "FALLTP") FallbackTPPips = MathMax(0, (int)StringToInteger(val));
   else if(key == "MAXTPS") MaxTPTargets = (int)TCU_ClampDouble((double)StringToInteger(val), 1, 3);
   else if(key == "SIGTP1PCT") TCU_SetSignalTpAlloc(1, StringToDouble(val));
   else if(key == "SIGTP2PCT") TCU_SetSignalTpAlloc(2, StringToDouble(val));
   else if(key == "SIGTP3PCT") TCU_SetSignalTpAlloc(3, StringToDouble(val));
   else if(key == "SIGTP1LOT") TCU_SetSignalTpFixedLot(1, StringToDouble(val));
   else if(key == "SIGTP2LOT") TCU_SetSignalTpFixedLot(2, StringToDouble(val));
   else if(key == "SIGTP3LOT") TCU_SetSignalTpFixedLot(3, StringToDouble(val));
   else if(key == "TRAILSTART") TrailStartPips = MathMax(1, (int)StringToInteger(val));
   else if(key == "TRAILDIST") TrailDistancePips = MathMax(1, (int)StringToInteger(val));
   else if(key == "TRAILSTEP") TrailStepPips = MathMax(1, (int)StringToInteger(val));
   else if(key == "BEBUFFER") BreakevenBufferPips = MathMax(0, (int)StringToInteger(val));
   else if(key == "TGBEEXTRA") TGBreakevenExtraPips = MathMax(0, (int)StringToInteger(val));
   else if(key == "CUSTOMSLKW") CustomSLKeywords = val;
   else if(key == "CUSTOMTPKW") CustomTPKeywords = val;
   else if(key == "PTP1") PartialTP1Pips = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP1PCT") PartialTP1Percent = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP1LOTS") PartialTP1Lots = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP2") PartialTP2Pips = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP2PCT") PartialTP2Percent = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP2LOTS") PartialTP2Lots = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP3") PartialTP3Pips = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP3PCT") PartialTP3Percent = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP3LOTS") PartialTP3Lots = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP4") PartialTP4Pips = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP4PCT") PartialTP4Percent = MathMax(0.0, StringToDouble(val));
   else if(key == "PTP4LOTS") PartialTP4Lots = MathMax(0.0, StringToDouble(val));
   else if(key == "PBEEXTRA") PartialBEExtraPips = MathMax(0, (int)StringToInteger(val));
   else if(key == "LOTDIST") LotDistribution = val;
   else if(key == "NEWSBEFORE") NewsPauseBeforeMinutes = MathMax(0, (int)StringToInteger(val));
   else if(key == "NEWSAFTER") NewsPauseAfterMinutes = MathMax(0, (int)StringToInteger(val));
   else if(key == "NEWSCUR") NewsPauseCurrencies = val;
   else if(key == "NEWSEXTRA") TCU_SetNewsExtraCurrencies(val);
   else if(key == "TGTAG") TelegramSendTag = val;
   else if(key == "TGSUFFIX") TelegramSendSuffix = val;
   else if(key == "SENDBOT") SendBotToken = val;
   else if(key == "SENDCHAT") SendChatID = val;
   else if(key == "SOUNDFILE") AlertSoundFile = val;
   else if(key == "MAGIC") MagicNumber = MathMax(1, (int)StringToInteger(val));
   else if(key == "DIAGFILE") DiagLogFileName = val;
   else if(key == "PURGEDAYS") ReportPurgeDays = MathMax(1, (int)StringToInteger(val));
   else if(key == "SYMSUFFIX") SymbolSuffix = val;
   else if(key == "PROFNAME") g_tcuProfileName = val;
   // [MARTINGALE] UI typed inputs
   else if(key == "MG_MULT") MartingaleMultiplier = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 1.1, 100.0), 2);
   else if(key == "MG_STEP") MartingaleFixedStep = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, 100.0), 2);
   else if(key == "MG_BASELOT") MartingaleBaseLot = NormalizeDouble(TCU_ClampDouble(StringToDouble(val), 0.01, 100.0), 2);
   else if(key == "MG_MAXSTEPS") MartingaleMaxSteps = MathMax(1, (int)StringToInteger(val));
   else if(key == "MG_MAXLOSS")  MartingaleMaxLoss = MathMax(0.0, StringToDouble(val));
   else return;

   if(FixedLotSize > MaxLotSize) FixedLotSize = MaxLotSize;
   if(CopierFixedLot > CopierMaxLot) CopierFixedLot = CopierMaxLot;
   if(key == "NEWSBEFORE" || key == "NEWSAFTER" || key == "NEWSCUR" || key == "NEWSEXTRA")
      TCU_LoadNewsCalendar();
   TCU_CommitSettings();
   TCU_DrawUI();
}

bool TCU_HandleEditEvent(const int id, const string &sparam)
{
   string pfx = TCUC_PFX + "ED_";
   if(StringFind(sparam, pfx) != 0) return false;
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      g_tcuActiveEdit = sparam;
      g_tcuActiveEditStart = ObjectGetString(0, sparam, OBJPROP_TEXT);
      return true;
   }
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      string key = StringSubstr(sparam, StringLen(pfx));
      string val = ObjectGetString(0, sparam, OBJPROP_TEXT);
      g_tcuActiveEdit = "";
      if(val == g_tcuActiveEditStart)
      {
         g_tcuActiveEditStart = "";
         return true;
      }
      g_tcuActiveEditStart = "";
      TCU_ApplyEditValue(key, val);
      return true;
   }
   return false;
}

void TCU_ProcessClick(string hit)
{
   if(hit == "") return;
   TCU_FlushActiveEdit();
   if(hit == "TCU_MONITOR")
   {
      if(g_tcuMonOpen)
      {
         g_tcuMonOpen = false;
         TCU_DestroyMonitorPopup();
      }
      else
      {
         TCU_OpenMonitorPopup();
         TCU_DrawMonitorPopup();
      }
      TCU_DrawUI();
      return;
   }
   if(StringFind(hit, "TCU_TAB_") == 0)
   {
      g_tcuTab = (int)StringToInteger(StringSubstr(hit, 8));
      TCU_DrawUI();
      return;
   }
   if(StringFind(hit, "TCU_SET_CAT_") == 0)
   {
      g_tcuSettingsCat = (int)StringToInteger(StringSubstr(hit, 12));
      TCU_DrawUI();
      return;
   }
   if(StringFind(hit, "TCU_ADJ_DEC_") == 0)
   {
      TCU_AdjustSetting(StringSubstr(hit, 12), -1);
      return;
   }
   if(StringFind(hit, "TCU_ADJ_INC_") == 0)
   {
      TCU_AdjustSetting(StringSubstr(hit, 12), 1);
      return;
   }
   if(StringFind(hit, "TCU_ADJ_VAL_") == 0)
   {
      Alert("[TCU] Use - / + to adjust this value. Direct typing will come in the next canvas editor pass.");
      return;
   }
   // [v6.00 NEW][PerSymUI] Open the Per-Symbol Lots configurator modal.
   if(hit == "TCU_PSL_OPEN")
   {
      if(g_tcuPslOpen)
      {
         bool wasMG = g_tcuPslIsMGMode;
         g_tcuPslIsMGMode = false;
         if(wasMG) { g_pslLastSerialized = ""; g_pslLastParseWasMG = false; }
         g_tcuPslOpen = false;
         TCU_DestroyPerSymPopup();
      }
      else
      {
         g_tcuPslIsMGMode = false;  // always open main lots popup from Lots tab
         g_pslLastParseWasMG = true;  // force re-parse (mode change from any prior MG parse)
         TCU_OpenPerSymPopup();
         TCU_DrawPerSymPopup();
      }
      TCU_DrawUI();
      return;
   }
   // [v6.00 NEW][PerSymUI] "Add" button on Lots tab. Reads the symbol typed in PSLADD edit box,
   // validates against MarketWatch via Psl_AddEntry, and shows status banner.
   if(hit == "TCU_PSL_ADD")
   {
      string addName = TCUC_PFX + "ED_PSLADD";
      string typed = (ObjectFind(0, addName) >= 0) ? ObjectGetString(0, addName, OBJPROP_TEXT) : g_tcuPslAddInputCache;
      bool _m = g_tcuPslIsMGMode; g_tcuPslIsMGMode = false;  // panel Add always targets main lots
      string status = Psl_AddEntry(typed, 0.01);
      g_tcuPslIsMGMode = _m;
      g_tcuPslAddBanner   = status;
      g_tcuPslAddBannerAt = GetTickCount64();
      bool added = (StringFind(status, "Added ") == 0);
      if(added)
      {
         g_tcuPslAddInputCache = "";
         if(ObjectFind(0, addName) >= 0) ObjectSetString(0, addName, OBJPROP_TEXT, "");
      }
      TCU_DrawUI();
      if(g_tcuPslOpen) TCU_DrawPerSymPopup();
      return;
   }
   if(hit == "TCU_PART_MODE")
   {
      PartialCloseMode = (PartialCloseMode == PARTIAL_PERCENTAGE ? PARTIAL_FIXED_LOTS : PARTIAL_PERCENTAGE);
      TCU_CommitSettings();
      return;
   }
   if(hit == "TCU_SIGTP_MODE")
   {
      SignalTpAllocMode = (SignalTpAllocMode == PARTIAL_PERCENTAGE ? PARTIAL_FIXED_LOTS : PARTIAL_PERCENTAGE);
      TCU_CommitSettings();
      return;
   }
   if(StringFind(hit, "TCU_PART_ON_") == 0)
   {
      int lvl = (int)StringToInteger(StringSubstr(hit, 12));
      if(lvl == 1) PartialTP1Pips = (PartialTP1Pips > 0 ? 0 : 20);
      else if(lvl == 2) PartialTP2Pips = (PartialTP2Pips > 0 ? 0 : 40);
      else if(lvl == 3) PartialTP3Pips = (PartialTP3Pips > 0 ? 0 : 60);
      else if(lvl == 4) PartialTP4Pips = (PartialTP4Pips > 0 ? 0 : 80);
      if(PartialCloseMode == PARTIAL_PERCENTAGE)
      {
         if(lvl == 1 && PartialTP1Percent <= 0) PartialTP1Percent = 25;
         if(lvl == 2 && PartialTP2Percent <= 0) PartialTP2Percent = 25;
         if(lvl == 3 && PartialTP3Percent <= 0) PartialTP3Percent = 25;
         if(lvl == 4 && PartialTP4Percent <= 0) PartialTP4Percent = 25;
      }
      else
      {
         if(lvl == 1 && PartialTP1Lots <= 0) PartialTP1Lots = 0.01;
         if(lvl == 2 && PartialTP2Lots <= 0) PartialTP2Lots = 0.01;
         if(lvl == 3 && PartialTP3Lots <= 0) PartialTP3Lots = 0.01;
         if(lvl == 4 && PartialTP4Lots <= 0) PartialTP4Lots = 0.01;
      }
      TCU_CommitSettings();
      return;
   }
   if(hit == "TCU_PART_MV_1") { PartialMoveSLBreakeven = !PartialMoveSLBreakeven; TCU_CommitSettings(); return; }
   if(hit == "TCU_PART_MV_2") { PartialMoveSLToTP1 = !PartialMoveSLToTP1; TCU_CommitSettings(); return; }
   if(hit == "TCU_PART_MV_3") { PartialMoveSLToTP2 = !PartialMoveSLToTP2; TCU_CommitSettings(); return; }
   if(hit == "TCU_PART_MV_4") { PartialMoveSLToTP3 = !PartialMoveSLToTP3; TCU_CommitSettings(); return; }
   if(hit == "TCU_MIN") { g_minimized = true; TCU_DrawUI(); return; }
   if(hit == "TCU_MAX") { g_minimized = false; TCU_DrawUI(); return; }
   if(hit == "TCU_CLOSE")
   {
      g_tcuClosed = true;
      _ScDeleteAll();
      TCU_DestroyCanvas();
      ChartRedraw();
      return;
   }
   if(hit == "TCU_SETTINGS") { g_tcuTab = 14; g_tcuSettingsCat = 8; TCU_DrawUI(); return; }
   if(hit == "TCU_ARM") { ArmExecution = !ArmExecution; g_lastFilterReason = ArmExecution ? "" : "DISARMED"; if(ArmExecution) g_botSessionStartTime = TimeGMT(); TCU_CommitSettings(); return; }
   if(hit == "TCU_COPIER_CLOSE") { CopierAutoClose = !CopierAutoClose; TCU_CommitSettings(); return; }
   if(hit == "TCU_REVERSE") { ReverseSignal = !ReverseSignal; TCU_CommitSettings(); return; }
   if(hit == "TCU_COPYSL") { CopySL = !CopySL; TCU_CommitSettings(); return; }
   if(hit == "TCU_COPYTP") { CopyTP = !CopyTP; TCU_CommitSettings(); return; }
   if(hit == "TCU_PROP") { PropFirmMode = !PropFirmMode; TCU_CommitSettings(); return; }
   if(hit == "TCU_DUP") { EnableDuplicateFilter = !EnableDuplicateFilter; TCU_CommitSettings(); return; }
   if(hit == "TCU_SPREAD") { EnableSpreadFilter = !EnableSpreadFilter; TCU_CommitSettings(); return; }
   if(hit == "TCU_TRAIL") { EnableTrailingStop = !EnableTrailingStop; TCU_CommitSettings(); return; }
   if(hit == "TCU_PARTIAL") { EnablePartialClose = !EnablePartialClose; TCU_CommitSettings(); return; }
   if(hit == "TCU_MULTITP") { EnableMultiTP = !EnableMultiTP; TCU_CommitSettings(); return; }
   if(hit == "TCU_PENDING") { EnablePendingOrders = !EnablePendingOrders; TCU_CommitSettings(); return; }
   if(hit == "TCU_PEXP") { EnablePendingExpiry = !EnablePendingExpiry; TCU_CommitSettings(); return; }
   if(hit == "TCU_MODSTACK") { AllowSLTPModDuringCooldown = !AllowSLTPModDuringCooldown; TCU_CommitSettings(); return; }
   if(hit == "TCU_TEST")
   {
      TCU_RunConnectionTest();
      return;
   }
   if(hit == "TCU_NEWS_RELOAD" || hit == "TCU_NEWS_LOAD")
   {
      TCU_LoadNewsCalendar();
      TCU_DrawUI();
      return;
   }
   if(hit == "TCU_NEWS_TOGGLE")
   {
      EnableNewsPause = !EnableNewsPause;
      if(EnableNewsPause) TCU_LoadNewsCalendar();
      TCU_CommitSettings();
      return;
   }

   if(hit == "TCU_SET_BOT") { EnableBotAPIMode = !EnableBotAPIMode; if(EnableBotAPIMode) TCU_BotApiActivate(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_BRIDGE") { bool was = EnableBridgeMode; EnableBridgeMode = !EnableBridgeMode; if(!was && EnableBridgeMode) TCU_BridgeActivate(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_DISCORD") { bool was=EnableDiscordMode; EnableDiscordMode = !EnableDiscordMode; if(!was && EnableDiscordMode) ArmDiscordSenderFresh(); else ClearDiscordSendQueue(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_TGSEND" || hit == "TCU_SET_TGSEND2") { bool was=EnableTelegramSend; EnableTelegramSend = !EnableTelegramSend; if(!was && EnableTelegramSend) ArmTelegramSenderFresh(); else ClearTelegramSendQueue(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_COPIERMODE") { _Cycle_CopierMode(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_COPIERSTARTUP") { _Cycle_CopierStartupCopyMode(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_COPIERLOTMODE") { _Cycle_CopierLotMode(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_COPIERCOMMENTMODE") { _Cycle_CopierTradeCommentMode(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_COPIERCLOSE") { CopierAutoClose = !CopierAutoClose; TCU_CommitSettings(); return; }
    if(hit == "TCU_SET_LOTMODE") { _Cycle_LotMode(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SKIPLOT") { SkipIfLotOverMax = !SkipIfLotOverMax; TCU_CommitSettings(); return; }
   if(hit == "TCU_FILTER_UP") { if(g_tcuFilterScroll > 0) g_tcuFilterScroll--; TCU_DrawUI(); return; }
   if(hit == "TCU_FILTER_DOWN") { if(g_tcuFilterScroll < 5) g_tcuFilterScroll++; TCU_DrawUI(); return; }
   if(hit == "TCU_FILTER_DUPLICATE") { g_tcuFilterScroll = 5; TCU_DrawUI(); return; }
   if(hit == "TCU_FILTER_COOLDOWN") { g_tcuFilterScroll = 4; TCU_DrawUI(); return; }
   if(hit == "TCU_SET_DUP") { EnableDuplicateFilter = !EnableDuplicateFilter; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SPREAD") { EnableSpreadFilter = !EnableSpreadFilter; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SLIP") { EnableSlippageFilter = !EnableSlippageFilter; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SLIPACT") { _Cycle_SlippageAction(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_WHITELIST") { EnableWhitelist = !EnableWhitelist; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_BLACKLIST") { EnableBlacklist = !EnableBlacklist; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SKIPKW") { EnableSkipKeywords = !EnableSkipKeywords; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_ARMOUR") { RequireEntryArmour = !RequireEntryArmour; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_KWREPLACE") { EnableKeywordReplace = !EnableKeywordReplace; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SKIPNOSL") { SkipSignalWithoutSL = !SkipSignalWithoutSL; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SKIPNOTP") { SkipSignalWithoutTP = !SkipSignalWithoutTP; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_TIMEFILTER") { EnableTimeFilter = !EnableTimeFilter; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SLTPINCD") { AllowSLTPModDuringCooldown = !AllowSLTPModDuringCooldown; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_ARM") { ArmExecution = !ArmExecution; g_lastFilterReason = ArmExecution ? "" : "DISARMED"; if(ArmExecution) g_botSessionStartTime = TimeGMT(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_REVERSE") { ReverseSignal = !ReverseSignal; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_COPYSL") { CopySL = !CopySL; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_COPYTP") { CopyTP = !CopyTP; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_OPPACT") { _Cycle_OppositeAction(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_PENDING") { EnablePendingOrders = !EnablePendingOrders; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_PEXP") { EnablePendingExpiry = !EnablePendingExpiry; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_MODSTACK") { AllowSLTPModDuringCooldown = !AllowSLTPModDuringCooldown; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_CMDREPLIES") { EnableCommandReplies = !EnableCommandReplies; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_AUTOSL") { EnableAutoSL = !EnableAutoSL; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_AUTOTP") { EnableAutoTP = !EnableAutoTP; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SIGNALTP") { EnableSignalTP = !EnableSignalTP; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_CUSTOMSLTP") { EnableCustomSLTPKeywords = !EnableCustomSLTPKeywords; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_TRAIL") { EnableTrailingStop = !EnableTrailingStop; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_TRAILBE") { TrailMoveToBreakeven = !TrailMoveToBreakeven; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_PARTIAL") { EnablePartialClose = !EnablePartialClose; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_PARTSCOPE") { _Cycle_PartialScope(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_MULTITP") { EnableMultiTP = !EnableMultiTP; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_PENDMTP") { EnablePendingMultiTP = !EnablePendingMultiTP; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_TGBE") { TGMoveSLBreakevenTP1 = !TGMoveSLBreakevenTP1; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_TGTP1") { TGMoveSLToTP1OnTP2 = !TGMoveSLToTP1OnTP2; TCU_CommitSettings(); return; }
   if(StringFind(hit, "TCU_SIGTP_ON_") == 0)
   {
      int lvl = (int)StringToInteger(StringSubstr(hit, 13));
      if(lvl >= 1 && lvl <= 3)
         MaxTPTargets = (MaxTPTargets == lvl ? MathMax(1, lvl - 1) : lvl);
      TCU_CommitSettings();
      return;
   }
   if(hit == "TCU_SET_NEWSPAUSE") { EnableNewsPause = !EnableNewsPause; if(EnableNewsPause) TCU_LoadNewsCalendar(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_COOLDOWN") { TCU_SetCooldownEnabled(!TCU_CooldownEnabled()); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_NEWSHIGH") { NewsPauseHighImpact = !NewsPauseHighImpact; TCU_LoadNewsCalendar(); TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_NEWSMED") { NewsPauseMediumImpact = !NewsPauseMediumImpact; TCU_LoadNewsCalendar(); TCU_CommitSettings(); return; }
   if(hit == "TCU_NEWS_IMPACT_ALL") { NewsPauseHighImpact = true; NewsPauseMediumImpact = true; TCU_LoadNewsCalendar(); TCU_CommitSettings(); return; }
   if(hit == "TCU_NEWS_IMPACT_HIGH") { NewsPauseHighImpact = true; NewsPauseMediumImpact = false; TCU_LoadNewsCalendar(); TCU_CommitSettings(); return; }
   if(hit == "TCU_NEWS_IMPACT_MED") { NewsPauseHighImpact = false; NewsPauseMediumImpact = true; TCU_LoadNewsCalendar(); TCU_CommitSettings(); return; }
   if(StringFind(hit, "TCU_NEWS_CUR_") == 0)
   {
      string cur = StringSubstr(hit, 13);
      TCU_ToggleNewsCurrency(cur);
      g_tcuNewsScroll = 0;
      TCU_LoadNewsCalendar();
      TCU_CommitSettings();
      return;
   }
   if(hit == "TCU_NEWS_UP") { if(g_tcuNewsScroll > 0) g_tcuNewsScroll--; TCU_DrawUI(); return; }
   if(hit == "TCU_NEWS_DOWN") { g_tcuNewsScroll++; TCU_DrawUI(); return; }
   if(hit == "TCU_SET_POPUP") { EnablePopupAlerts = !EnablePopupAlerts; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SOUND") { EnableSoundAlerts = !EnableSoundAlerts; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_PUSH") { EnablePushNotify = !EnablePushNotify; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_PARTALERT") { EnablePartialAlerts = !EnablePartialAlerts; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_CMDREPLY") { EnableCommandReplies = !EnableCommandReplies; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_SENDBOT") { UseSeparateSendBot = !UseSeparateSendBot; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_PROP") { PropFirmMode = !PropFirmMode; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_DIAG") { EnableDiagLog = !EnableDiagLog; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_REPORT") { EnableReportLog = !EnableReportLog; TCU_CommitSettings(); return; }
   if(hit == "TCU_SET_RESTARTDISARM") { DisarmOnRestart = !DisarmOnRestart; TCU_CommitSettings(); return; }

   // MG Per-Symbol Lots popup toggle
   if(hit == "TCU_MG_PERSYM_OPEN")
   {
      if(g_tcuPslOpen && g_tcuPslIsMGMode)
      {
         g_tcuPslIsMGMode = false;
         g_pslLastSerialized = ""; // force Lots-tab re-parse after MG popup
         g_tcuPslOpen = false;
         TCU_DestroyPerSymPopup();
      }
      else
      {
         if(g_tcuPslOpen) { g_pslLastSerialized = ""; TCU_DestroyPerSymPopup(); g_tcuPslOpen = false; }
         g_tcuPslIsMGMode = true;
         g_mgpslLastSerialized = ""; // force MG re-parse on open
         TCU_OpenPerSymPopup();
         TCU_DrawPerSymPopup();
      }
      TCU_DrawUI(); return;
   }
   // -- MARTINGALE HIT HANDLERS --
   if(hit == "TCU_ADV_SET_OPEN")  { TCU_OpenAdvPopup(); TCU_DrawAdvPopup(); TCU_DrawUI(); return; }
   if(hit == "TCU_ADV_SET_CLOSE") { g_tcuAdvSetOpen=false; TCU_DestroyAdvPopup(); TCU_DrawUI(); return; }
   if(hit == "TCU_ADV_RESET_ALL")
   {
      int confirm = MessageBox("Reset ALL Martingale streaks and P&L?\n\nThis clears the recovery state for every symbol.",
                               "TradeCopierUltimate - Reset All", MB_YESNO | MB_ICONWARNING);
      if(confirm == IDYES)
      {
         MG_ResetAll();
         TCU_CommitSettings();
      }
      TCU_DrawUI(); return;
   }
   if(hit == "TCU_MG_AGREE")
   {
      int confirm = MessageBox(
         "RISK DISCLAIMER\n\n"
         "Martingale and Advanced modes can cause rapid account loss.\n"
         "Lot sizes increase after losses, compounding your risk.\n\n"
         "We are NOT responsible for any financial losses.\n\n"
         "Do you accept full responsibility and wish to proceed?",
         "TradeCopierUltimate - Risk Acknowledgement",
         MB_YESNO | MB_ICONWARNING);
      if(confirm == IDYES)
      {
         g_mgDisclaimerAccepted = true;
         Print("[MG] User accepted martingale risk disclaimer");
      }
      TCU_DrawUI(); return;
   }
   if(hit == "TCU_MG_TOGGLE")
   {
      if(!EnableMartingale)
      {
         EnableMartingale = true;
         MG_StartFreshSeries("Martingale enabled -- historical loss streaks ignored");
      }
      else
      {
         EnableMartingale = false;
         g_mgActivationTime = 0;
         MG_ClearDealCache();
         Print("[MG] Martingale disabled.");
      }
      TCU_CommitSettings(); return;
   }
   if(hit == "TCU_MG_HELP")      { g_mgHelpOpen = !g_mgHelpOpen; g_mgHelpPage = 0; TCU_DrawUI(); return; }
   if(hit == "TCU_MG_HELP_PREV") { if(g_mgHelpPage > 0) g_mgHelpPage--; TCU_DrawUI(); return; }
   if(hit == "TCU_MG_HELP_NEXT") { if(g_mgHelpPage < 4) g_mgHelpPage++; TCU_DrawUI(); return; }
   if(hit == "TCU_MGTAB_STRAT")
   {
      g_mgViewTab = 0; // navigate to Strategies view (does NOT change active mode)
      TCU_DrawUI(); return;
   }
   if(hit == "TCU_MGTAB_REC")
   {
      g_mgViewTab = 1; // navigate to Recovery view (does NOT change active mode)
      TCU_DrawUI(); return;
   }
   if(hit == "TCU_MG_ACTIVATE_STRAT")
   {
      if(MartingaleMode == 4) MartingaleMode = 0; // explicitly activate strategy (Classic default)
      TCU_CommitSettings(); TCU_DrawUI(); return;
   }
   if(hit == "TCU_MG_ACTIVATE_REC")
   {
      MartingaleMode = 4; // explicitly activate Recovery mode
      TCU_CommitSettings(); TCU_DrawUI(); return;
   }
   if(hit == "TCU_MG_MODE")
   {
      MartingaleMode = (MartingaleMode + 1) % 4; // Cycle only 0..3 on Strategy tab
      TCU_CommitSettings(); return;
   }
   if(hit == "TCU_MG_RESETWIN")
   {
      MartingaleResetOnWin = !MartingaleResetOnWin;
      TCU_CommitSettings(); return;
   }
   if(hit == "TCU_MG_RESETALL")
   {
      MG_ResetAll();
      TCU_CommitSettings();
      TCU_DrawUI(); return;
   }
   // Per-symbol reset buttons: TCU_MG_RST_0 .. TCU_MG_RST_N
   if(StringFind(hit, "TCU_MG_RST_") == 0)
   {
      int idx = (int)StringToInteger(StringSubstr(hit, 11));
      if(idx >= 0 && idx < g_mgCount)
         MG_Reset(g_mgTable[idx].sym);
      TCU_DrawUI(); return;
   }
   if(hit == "TCU_MG_MONITOR")
   {
      if(g_mgmOpen) { g_mgmOpen = false; TCU_DestroyMGMonitor(); }
      else          { TCU_OpenMGMonitor(); TCU_DrawMGMonitor(); }
      TCU_DrawUI(); return;
   }
   if(hit == "TCU_PROF_TOGGLE") { if(!g_tcuProfileOpen){TCU_OpenProfilesPopup();TCU_DrawProfilesPopup();}else{g_tcuProfileOpen=false;TCU_DestroyProfilesPopup();} TCU_DrawUI(); return; }
   if(hit == "TCU_PROF_SAVE") { TCU_ExportProfile(g_tcuProfileName); TCU_DrawProfilesPopup(); TCU_DrawUI(); return; }
   if(hit == "TCU_PROF_LOAD") { TCU_ImportProfile(g_tcuProfileName); TCU_CommitSettings(); TCU_DrawProfilesPopup(); TCU_DrawUI(); return; }
}

bool TCU_HandleCanvasEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!g_tcuCanvasCreated && !g_tcuClosed) return false;
   if(id != CHARTEVENT_MOUSE_MOVE && id != CHARTEVENT_CLICK) return false;

   int mx = (int)lparam;
   int my = (int)dparam;
   bool isMouseMove = (id == CHARTEVENT_MOUSE_MOVE);
   bool isClick = (id == CHARTEVENT_CLICK);
   int mask = isMouseMove ? (int)StringToInteger(sparam) : 0;
   bool leftDown = isMouseMove && ((mask & 1) != 0);

   // [MG Monitor] Route mouse events to MG Monitor popup first when open.
   if(g_mgmOpen)
   {
      int mgx = mx - g_mgmX;
      int mgy = my - g_mgmY;
      bool insideMgm = (mgx >= 0 && mgy >= 0 && mgx < TCU_MGM_W && mgy < TCU_MGM_H);
      string mgmHit = insideMgm ? TCU_MGMHitTest(mgx, mgy) : "";
      if(mgmHit != g_mgmHovered) g_mgmHovered = mgmHit;

      if(leftDown && !g_mgmMouseWasDown && insideMgm)
      {
         g_mgmMouseWasDown = true;
         g_mgmMouseDownX = mx; g_mgmMouseDownY = my;
         g_mgmMouseDownHit = mgmHit; g_mgmPressed = mgmHit;
         if(mgmHit == "" && mgy <= 36)
         {
            g_mgmDragging = true;
            g_mgmDragOffsetX = mx - g_mgmX;
            g_mgmDragOffsetY = my - g_mgmY;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }
         return true;
      }
      if(isClick && !g_mgmMouseWasDown && insideMgm && mgmHit != "")
      {
         TCU_ProcessMGMonitorClick(mgmHit);
         return true;
      }
      if(leftDown && g_mgmDragging)
      {
         g_mgmX = mx - g_mgmDragOffsetX;
         g_mgmY = my - g_mgmDragOffsetY;
         TCU_DrawMGMonitor();
         return true;
      }
      if(!leftDown && g_mgmMouseWasDown)
      {
         bool wasDrag = g_mgmDragging;
         g_mgmDragging = false; g_mgmMouseWasDown = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         string downHit = g_mgmMouseDownHit; g_mgmPressed = "";
         int dx = MathAbs(mx - g_mgmMouseDownX), dy = MathAbs(my - g_mgmMouseDownY);
         if(!wasDrag && downHit != "" && downHit == mgmHit && dx <= 6 && dy <= 6)
            TCU_ProcessMGMonitorClick(downHit);
         else
            TCU_DrawMGMonitor();
         return true;
      }
      if(insideMgm || g_mgmDragging) return true;
   }

   // [ADV] Advanced Settings popup mouse routing
   if(g_tcuAdvSetOpen)
   {
      int ax=mx-g_advX, ay=my-g_advY;
      bool insideAdv=(ax>=0&&ay>=0&&ax<TCU_ADV_W&&ay<TCU_ADV_H);
      string advHit=insideAdv?TCU_ADVHitTest(ax,ay):"";
      if(advHit!=g_advHovered) g_advHovered=advHit;
      if(leftDown&&!g_advMouseWasDown&&insideAdv)
      {
         g_advMouseWasDown=true;
         g_advMouseDownX=mx; g_advMouseDownY=my;
         g_advMouseDownHit=advHit; g_advPressed=advHit;
         if(advHit==""&&ay<=36)
         { g_advDragging=true; g_advDragOffsetX=mx-g_advX; g_advDragOffsetY=my-g_advY;
           ChartSetInteger(0,CHART_MOUSE_SCROLL,false); }
         return true;
      }
      if(isClick&&!g_advMouseWasDown&&insideAdv&&advHit!="")
         { TCU_ProcessAdvClick(advHit); return true; }
      if(leftDown&&g_advDragging)
         { g_advX=mx-g_advDragOffsetX; g_advY=my-g_advDragOffsetY; TCU_DrawAdvPopup(); return true; }
      if(!leftDown&&g_advMouseWasDown)
      {
         bool wasDrag=g_advDragging;
         g_advDragging=false; g_advMouseWasDown=false;
         ChartSetInteger(0,CHART_MOUSE_SCROLL,true);
         string dHit=g_advMouseDownHit; g_advPressed="";
         int dx=MathAbs(mx-g_advMouseDownX),dy=MathAbs(my-g_advMouseDownY);
         if(!wasDrag&&dHit!=""&&dHit==advHit&&dx<=6&&dy<=6) TCU_ProcessAdvClick(dHit);
         TCU_DrawAdvPopup();
      }
      if(insideAdv||g_advDragging) return true;
   }

   // [PROF] Profiles popup mouse routing
   if(g_tcuProfileOpen)
   {
      int px=mx-g_profX,py=my-g_profY;
      bool insideProf=(px>=0&&py>=0&&px<TCU_PROF_W&&py<TCU_PROF_H);
      string profHit=insideProf?TCU_PROFHitTest(px,py):"";
      if(profHit!=g_profHovered) g_profHovered=profHit;
      if(leftDown&&!g_profMouseWasDown&&insideProf)
      {
         g_profMouseWasDown=true; g_profMouseDownX=mx; g_profMouseDownY=my;
         g_profMouseDownHit=profHit; g_profPressed=profHit;
         if(profHit==""&&py<=36){g_profDragging=true;g_profDragOffsetX=mx-g_profX;g_profDragOffsetY=my-g_profY;ChartSetInteger(0,CHART_MOUSE_SCROLL,false);}
         return true;
      }
      if(isClick&&!g_profMouseWasDown&&insideProf&&profHit!="")
         {TCU_ProcessProfClick(profHit);return true;}
      if(leftDown&&g_profDragging)
         {g_profX=mx-g_profDragOffsetX;g_profY=my-g_profDragOffsetY;TCU_DrawProfilesPopup();return true;}
      if(!leftDown&&g_profMouseWasDown)
      {
         bool wD=g_profDragging; g_profDragging=false; g_profMouseWasDown=false;
         ChartSetInteger(0,CHART_MOUSE_SCROLL,true);
         string dH=g_profMouseDownHit; g_profPressed="";
         int dx=MathAbs(mx-g_profMouseDownX),dy=MathAbs(my-g_profMouseDownY);
         if(!wD&&dH!=""&&dH==profHit&&dx<=6&&dy<=6) TCU_ProcessProfClick(dH);
         TCU_DrawProfilesPopup();
      }
      if(insideProf||g_profDragging) return true;
   }

   // [v6.00 NEW][PerSymUI] Route mouse to Per-Symbol Lots modal first when open.
   // Same pattern as Trade Monitor below: drag from title bar, click to dispatch hits.
   if(g_tcuPslOpen)
   {
      int psx = mx - g_tcuPslX;
      int psy = my - g_tcuPslY;
      bool insidePsl = (psx >= 0 && psy >= 0 && psx < TCU_PSL_W && psy < TCU_PSL_H);
      string pslHit = insidePsl ? TCU_PslHitTest(psx, psy) : "";
      if(pslHit != g_tcuPslHovered)
         g_tcuPslHovered = pslHit;

      if(leftDown && !g_tcuPslMouseWasDown && insidePsl)
      {
         g_tcuPslMouseWasDown = true;
         g_tcuPslMouseDownX = mx;
         g_tcuPslMouseDownY = my;
         g_tcuPslMouseDownHit = pslHit;
         g_tcuPslPressed = pslHit;
         if(pslHit == "" && psy <= 36)
         {
            g_tcuPslDragging = true;
            g_tcuPslDragOffsetX = mx - g_tcuPslX;
            g_tcuPslDragOffsetY = my - g_tcuPslY;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }
         return true;
      }

      if(isClick && !g_tcuPslMouseWasDown && insidePsl && pslHit != "")
      {
         TCU_ProcessPerSymClick(pslHit);
         return true;
      }

      if(leftDown && g_tcuPslDragging)
      {
         g_tcuPslX = mx - g_tcuPslDragOffsetX;
         g_tcuPslY = my - g_tcuPslDragOffsetY;
         TCU_DrawPerSymPopup();
         return true;
      }

      if(!leftDown && g_tcuPslMouseWasDown)
      {
         bool wasDraggingPsl = g_tcuPslDragging;
         g_tcuPslDragging = false;
         g_tcuPslMouseWasDown = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         string downPslHit = g_tcuPslMouseDownHit;
         g_tcuPslPressed = "";
         int pdx2 = MathAbs(mx - g_tcuPslMouseDownX);
         int pdy2 = MathAbs(my - g_tcuPslMouseDownY);
         if(!wasDraggingPsl && downPslHit != "" && downPslHit == pslHit && pdx2 <= 6 && pdy2 <= 6)
            TCU_ProcessPerSymClick(downPslHit);
         else
            TCU_DrawPerSymPopup();
         return true;
      }

      if(insidePsl || g_tcuPslDragging)
         return true;
   }

   if(g_tcuMonOpen)
   {
      int pmx = mx - g_tcuMonX;
      int pmy = my - g_tcuMonY;
      bool insideMon = (pmx >= 0 && pmy >= 0 && pmx < TCUO_W && pmy < TCUO_H);
      string monHit = insideMon ? TCU_MonHitTest(pmx, pmy) : "";
      if(monHit != g_tcuMonHovered)
         g_tcuMonHovered = monHit;

      if(leftDown && !g_tcuMonMouseWasDown && insideMon)
      {
         g_tcuMonMouseWasDown = true;
         g_tcuMonMouseDownX = mx;
         g_tcuMonMouseDownY = my;
         g_tcuMonMouseDownHit = monHit;
         g_tcuMonPressed = monHit;
         if(monHit == "" && pmy <= 36)
         {
            g_tcuMonDragging = true;
            g_tcuMonDragOffsetX = mx - g_tcuMonX;
            g_tcuMonDragOffsetY = my - g_tcuMonY;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }
         return true;
      }

      if(isClick && !g_tcuMonMouseWasDown && insideMon && monHit != "")
      {
         TCU_ProcessMonitorClick(monHit);
         return true;
      }

      if(leftDown && g_tcuMonDragging)
      {
         g_tcuMonX = mx - g_tcuMonDragOffsetX;
         g_tcuMonY = my - g_tcuMonDragOffsetY;
         TCU_DrawMonitorPopup();
         return true;
      }

      if(!leftDown && g_tcuMonMouseWasDown)
      {
         bool wasDraggingMon = g_tcuMonDragging;
         g_tcuMonDragging = false;
         g_tcuMonMouseWasDown = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         string downMonHit = g_tcuMonMouseDownHit;
         g_tcuMonPressed = "";
         int pdx = MathAbs(mx - g_tcuMonMouseDownX);
         int pdy = MathAbs(my - g_tcuMonMouseDownY);
         if(!wasDraggingMon && downMonHit != "" && downMonHit == monHit && pdx <= 6 && pdy <= 6)
            TCU_ProcessMonitorClick(monHit);
         else
            TCU_DrawMonitorPopup();
         return true;
      }

      if(insideMon || g_tcuMonDragging)
         return true;
   }

   int lx = mx - g_panelX;
   int ly = my - g_panelY;
   bool inside = (lx >= 0 && ly >= 0 && lx < g_panelW && ly < g_panelH);
   string hit = inside ? TCU_HitTest(lx, ly) : "";

   if(hit != g_tcuHovered)
   {
      g_tcuHovered = hit;
   }

   if(isClick && !g_tcuMouseWasDown && inside && hit != "")
   {
      TCU_ProcessClick(hit);
      return true;
   }

   if(leftDown && !g_tcuMouseWasDown)
   {
      g_tcuMouseWasDown = true;
      g_tcuMouseDownX = mx;
      g_tcuMouseDownY = my;
      g_tcuMouseDownHit = hit;
      g_tcuPressed = hit;
      if(hit == "" && inside && ly <= 54)
      {
         g_tcuDragging = true;
         g_tcuDragOffsetX = mx - g_panelX;
         g_tcuDragOffsetY = my - g_panelY;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
      }
      return inside;
   }

   if(leftDown && g_tcuDragging)
   {
      TCU_MovePanel(mx - g_tcuDragOffsetX, my - g_tcuDragOffsetY);
      return true;
   }

   if(!leftDown && g_tcuMouseWasDown)
   {
      bool wasDragging = g_tcuDragging;
      g_tcuDragging = false;
      g_tcuMouseWasDown = false;
      ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
      string downHit = g_tcuMouseDownHit;
      g_tcuPressed = "";
      int dx = MathAbs(mx - g_tcuMouseDownX);
      int dy = MathAbs(my - g_tcuMouseDownY);
      if(!wasDragging && downHit != "" && downHit == hit && dx <= 6 && dy <= 6)
         TCU_ProcessClick(hit);
      else
         TCU_DrawUI();
      return inside || downHit != "";
   }

   return inside || g_tcuDragging;
}

int OnInit()
{
   // Initialize shadows from inputs
   EnableBotAPIMode = inp_EnableBotAPIMode;
   TelegramBotToken = inp_TelegramBotToken;
   TelegramChatID = inp_TelegramChatID;
   TelegramPollSeconds = inp_TelegramPollSeconds;
   EnableBridgeMode = inp_EnableBridgeMode;
   BridgePort = inp_BridgePort;
   BridgePollMs = inp_BridgePollMs;
   AllowedBridgeSources = inp_AllowedBridgeSources;
   EnableDiscordMode = inp_EnableDiscordMode;
   DiscordWebhookURL = inp_DiscordWebhookURL;
   DiscordPollSeconds = inp_DiscordPollSeconds;
   CopierMode = inp_CopierMode;
   CopierFileName = inp_CopierFileName;
   CopierAutoClose = inp_CopierAutoClose;
   CopierPollMs = inp_CopierPollMs;
   CopierStartupCopyMode = inp_CopierStartupCopyMode;
   CopierLotMode = inp_CopierLotMode;
   CopierFixedLot = inp_CopierFixedLot;
   CopierLotMultiplier = inp_CopierLotMultiplier;
   CopierRiskPercent = inp_CopierRiskPercent;
   CopierMaxLot = inp_CopierMaxLot;
   CopierMinimumLotToCopy = inp_CopierMinimumLotToCopy;
   CopierTradeCommentMode = inp_CopierTradeCommentMode;
   CopierCustomTradeComment = inp_CopierCustomTradeComment;
   EnableReportLog = inp_EnableReportLog;
   ReportPurgeDays = inp_ReportPurgeDays;
   EnableTelegramSend = inp_EnableTelegramSend;
   TelegramSendTag = inp_TelegramSendTag;
   TelegramSendSuffix = inp_TelegramSendSuffix;
   UseSeparateSendBot = inp_UseSeparateSendBot;
   SendBotToken = inp_SendBotToken;
   SendChatID = inp_SendChatID;
   LotMode = inp_LotMode;
   FixedLotSize = inp_FixedLotSize;
   LotMultiplier = inp_LotMultiplier;
   RiskPercent = inp_RiskPercent;
   PerSymbolLots = inp_PerSymbolLots;  // [v6.00 NEW][PerSymbolLots]
   MGPerSymbolLots = inp_MGPerSymbolLots;
   DefaultSLPoints = inp_DefaultSLPoints;
   MaxLotSize = inp_MaxLotSize;
   SkipIfLotOverMax = inp_SkipIfLotOverMax;
   MaxTradesPerMinute = inp_MaxTradesPerMinute;
   MaxOpenPositions = inp_MaxOpenPositions;
   MaxDailyLossPercent = inp_MaxDailyLossPercent;
   MaxDailyLossAmount = inp_MaxDailyLossAmount;
   DailyResetTimezone = inp_DailyResetTimezone;            // [v6.01 FIX]
   DailyLossUsePeakEquity = inp_DailyLossUsePeakEquity;    // [v6.01 FIX]
   SkipSignalWithoutSL = inp_SkipSignalWithoutSL;
   SkipSignalWithoutTP = inp_SkipSignalWithoutTP;
   EnableSignalTP = inp_EnableSignalTP;
   EnableAutoSL = inp_EnableAutoSL;
   FallbackSLPips = inp_FallbackSLPips;
   EnableAutoTP = inp_EnableAutoTP;
   FallbackTPPips = inp_FallbackTPPips;
   EnableTimeFilter = inp_EnableTimeFilter;
   TimeFilterStartHour = inp_TimeFilterStartHour;
   TimeFilterEndHour = inp_TimeFilterEndHour;
   SignalCooldownSeconds = inp_SignalCooldownMinutes * 60;

   AllowSLTPModDuringCooldown = inp_AllowSLTPModDuringCooldown;
   MinPipsDistanceSameType = inp_MinPipsDistanceSameType;
   EnableWhitelist = inp_EnableWhitelist;
   WhitelistSymbols = inp_WhitelistSymbols;
   EnableBlacklist = inp_EnableBlacklist;
   BlacklistSymbols = inp_BlacklistSymbols;
   EnableSkipKeywords = inp_EnableSkipKeywords;
   SkipKeywords = inp_SkipKeywords;
   EnablePendingOrders = inp_EnablePendingOrders;
   EnablePendingExpiry = inp_EnablePendingExpiry;

   EnablePendingMultiTP = inp_EnablePendingMultiTP;
   PendingExpiryHours = inp_PendingExpiryHours;
   RequireEntryArmour = inp_RequireEntryArmour;
   ModifySLTPIfPositionExists = inp_ModifySLTPIfPositionExists;
   CopySL = inp_CopySL;
   CopyTP = inp_CopyTP;
   ReverseSignal = inp_ReverseSignal;
   SymbolSuffix = inp_SymbolSuffix;
   CustomMappings = inp_CustomMappings;
   EnableCustomSLTPKeywords = inp_EnableCustomSLTPKeywords;
   CustomSLKeywords = inp_CustomSLKeywords;
   CustomTPKeywords = inp_CustomTPKeywords;
   EnableCommandReplies = inp_EnableCommandReplies;
   MoveSLCommands = inp_MoveSLCommands;
   CloseAllCommands = inp_CloseAllCommands;
   EnableKeywordReplace = inp_EnableKeywordReplace;
   KeywordReplaceMap = inp_KeywordReplaceMap;
   DisarmOnRestart = inp_DisarmOnRestart;
   EnableTrailingStop = inp_EnableTrailingStop;
   TrailStartPips = inp_TrailStartPips;
   TrailDistancePips = inp_TrailDistancePips;
   TrailStepPips = inp_TrailStepPips;
   TrailMoveToBreakeven = inp_TrailMoveToBreakeven;
   BreakevenBufferPips = inp_BreakevenBufferPips;
   EnablePartialClose = inp_EnablePartialClose;
   PartialScope = inp_PartialScope;
   PartialTP1Pips = inp_PartialTP1Pips;
   PartialTP1Lots = inp_PartialTP1Lots;
   PartialTP1Percent = inp_PartialTP1Percent;
   PartialTP2Pips = inp_PartialTP2Pips;
   PartialTP2Lots = inp_PartialTP2Lots;
   PartialTP2Percent = inp_PartialTP2Percent;
   PartialTP3Pips = inp_PartialTP3Pips;
   PartialTP3Lots = inp_PartialTP3Lots;
   PartialTP3Percent = inp_PartialTP3Percent;
   PartialTP4Pips = inp_PartialTP4Pips;
   PartialTP4Lots = inp_PartialTP4Lots;
   PartialTP4Percent = inp_PartialTP4Percent;
   PartialMoveSLBreakeven = inp_PartialMoveSLBreakeven;
   PartialBEExtraPips = inp_PartialBEExtraPips;
   PartialMoveSLToTP1 = inp_PartialMoveSLToTP1;
   PartialMoveSLToTP2 = inp_PartialMoveSLToTP2;
   PartialMoveSLToTP3 = inp_PartialMoveSLToTP3;
   EnableMultiTP = inp_EnableMultiTP;
   MaxTPTargets = inp_MaxTPTargets;
   SignalTpFixedOverrideMainLots = inp_SignalTpFixedOverrideMainLots;
   SignalTpAllocMode = inp_SignalTpAllocMode;
   LotDistribution = inp_LotDistribution;
   SignalTpLotValues = inp_SignalTpLotValues;
   TGMoveSLBreakevenTP1 = inp_TGMoveSLBreakevenTP1;
   TGMoveSLToTP1OnTP2 = inp_TGMoveSLToTP1OnTP2;
   TGBreakevenExtraPips = inp_TGBreakevenExtraPips;
   ArmExecution = inp_ArmExecution;
   EnableDuplicateFilter = inp_EnableDuplicateFilter;
   DuplicateWindowMinutes = MathMax(1, inp_DuplicateWindowMinutes);
   PropFirmMode = inp_PropFirmMode;
   g_showMartingaleTab = inp_ShowMartingaleTab && (inp_MartingalePassword == "NAVIGATOR-ADV");
   if(!g_showMartingaleTab && g_tcuTab == 13) g_tcuTab = 0;
   EnableDiagLog = inp_EnableDiagLog;
   DiagLogFileName = inp_DiagLogFileName;
   EnableNewsPause = inp_EnableNewsPause;
   NewsPauseBeforeMinutes = inp_NewsPauseBeforeMinutes;
   NewsPauseAfterMinutes = inp_NewsPauseAfterMinutes;
   NewsPauseHighImpact = inp_NewsPauseHighImpact;
   NewsPauseMediumImpact = inp_NewsPauseMediumImpact;
   NewsPauseCurrencies = inp_NewsPauseCurrencies;
   MagicNumber = inp_MagicNumber;
   PanelMode = inp_PanelMode;
   PartialCloseMode = inp_PartialCloseMode;
   PanelX = inp_PanelX;
   PanelY = inp_PanelY;
   EnableSpreadFilter = inp_EnableSpreadFilter;
   MaxSpreadPoints = inp_MaxSpreadPoints;
   EnableSlippageFilter = inp_EnableSlippageFilter;
   SlippagePoints = inp_SlippagePoints;
   EntrySlippagePips = inp_EntrySlippagePips;
   SlippageAction = inp_SlippageAction;
   OppositeAction = inp_OppositeAction;
   EnablePopupAlerts = inp_EnablePopupAlerts;
   EnableSoundAlerts = inp_EnableSoundAlerts;
   EnablePushNotify = inp_EnablePushNotify;
   EnablePartialAlerts = inp_EnablePartialAlerts;
   AlertSoundFile = inp_AlertSoundFile;

   g_isTester = (bool)MQLInfoInteger(MQL_TESTER);
   g_eaStartTime = TimeCurrent();

   g_startupTickCount = GetTickCount64();  // For 10s drain window
   
   Print("=== OnInit START ===");
   Print("CopierMode: ", EnumToString(CopierMode));
   Print("EnableBridgeMode: ", EnableBridgeMode);
   Print("EnableBotAPIMode: ", EnableBotAPIMode);
   Print("Tester: ", g_isTester);
   
   // Input validation
   if(MagicNumber <= 0)
   {
      Alert("Trade Copier: MagicNumber must be positive!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxLotSize <= 0)
   {
      Alert("Trade Copier: MaxLotSize must be positive!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(FixedLotSize <= 0)
   {
      Alert("Trade Copier: FixedLotSize must be positive!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(BridgePort <= 0 || BridgePort > 65535)
   {
      Alert("Trade Copier: BridgePort must be between 1 and 65535!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(BridgePollMs < 10 || BridgePollMs > 60000)
   {
      Alert("Trade Copier: BridgePollMs must be between 10 and 60000!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(CopierPollMs < 10 || CopierPollMs > 60000)
   {
      Alert("Trade Copier: CopierPollMs must be between 10 and 60000!");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(CopierMinimumLotToCopy < 0)
   {
      Alert("Trade Copier: CopierMinimumLotToCopy cannot be negative!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TelegramPollSeconds < 1 || TelegramPollSeconds > 300)
   {
      Alert("Trade Copier: TelegramPollSeconds must be between 1 and 300!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxSpreadPoints < 0)
   {
      Alert("Trade Copier: MaxSpreadPoints cannot be negative!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(SlippagePoints < 0)
   {
      Alert("Trade Copier: SlippagePoints cannot be negative!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(DefaultSLPoints < 0)
   {
      Alert("Trade Copier: DefaultSLPoints cannot be negative!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Netting account warning -- auto-close by ticket doesn't work reliably on netting
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
   {
      if(CopierMode == MODE_SLAVE && CopierAutoClose)
         Print("[WARNING] Netting account detected. Auto-close by ticket may not work correctly. Consider disabling CopierAutoClose or using a hedging account.");
      if(EnableBotAPIMode || EnableBridgeMode)
         Print("[WARNING] Netting account detected. Multiple signals for the same symbol will merge into one position.");
   }
   
   
   if(RiskPercent <= 0 || RiskPercent > 100)
   {
      Alert("Trade Copier: RiskPercent must be between 0 and 100!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Trailing stop input validation
   if(EnableTrailingStop)
   {
      if(TrailStartPips <= 0 || TrailDistancePips <= 0 || TrailStepPips <= 0)
      {
         Alert("Trade Copier: Trailing Stop pips values must be positive!");
         return INIT_PARAMETERS_INCORRECT;
      }
      if(TrailDistancePips >= TrailStartPips)
      {
         Print("[WARNING] TrailDistancePips (", TrailDistancePips, ") >= TrailStartPips (", TrailStartPips, "). Trailing may activate and immediately trail very close.");
      }
   }
   
   // Signal cooldown input validation
   if(SignalCooldownSeconds < 0)
   {
      Alert("Trade Copier: SignalCooldownSeconds cannot be negative!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Whitelist/Blacklist conflict warning
   if(EnableWhitelist && EnableBlacklist)
      Print("[WARNING] Both Whitelist and Blacklist are enabled. Whitelist takes priority.");
   
   if(MaxTPTargets < 1) MaxTPTargets = 1;
   if(MaxTPTargets > 3) MaxTPTargets = 3;
   
   Print("[INIT] Input validation passed");
   
   // -- HARD BLOCK: BotAPI mode needs token + chatID -------------------------------------
   if(EnableBotAPIMode)
   {
      if(StringLen(TelegramBotToken) < 10)
      {
         Alert("[X] TCU: Bot API mode is ON but TelegramBotToken is empty!\nAdd your token from @BotFather and restart the EA.");
         return INIT_PARAMETERS_INCORRECT;
      }
      if(StringLen(TelegramChatID) == 0)
      {
         Alert("[X] TCU: Bot API mode is ON but TelegramChatID is empty!\nUse @userinfobot to get your Chat ID and restart the EA.");
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   if(EnableDiscordMode && StringLen(DiscordWebhookURL) < 10)
   {
      Alert("[X] TCU: Discord Send is ON but DiscordWebhookURL is empty!\nPaste your Discord webhook URL and restart the EA.");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // -- MULTI-MODE COLLISION WARNING -- only count EXPLICITLY enabled modes -----------------
   // (auto-detected bot from token is a helper, not a conflict -- don't warn for it)
   int activeModes = 0;
   if(EnableBotAPIMode)   activeModes++;
   if(EnableBridgeMode)   activeModes++;
   if(activeModes > 1)
      Alert("[!] TCU Warning: " + IntegerToString(activeModes) + " signal sources enabled simultaneously.\nThis can cause duplicate trades. Recommended: use Bridge OR Bot, not both.");
   
   // -- MODE SAFETY: enforce via effective limits, do NOT overwrite the user's saved values
   bool migratedModeValues = false;
   if(!PropFirmMode)
   {
      // Heal old persisted values that were permanently mutated by pre-fix mode enforcement.
      if(MaxOpenPositions == 2 && inp_MaxOpenPositions > 2) { MaxOpenPositions = inp_MaxOpenPositions; migratedModeValues = true; }
      else if(MaxOpenPositions == 5 && inp_MaxOpenPositions > 5) { MaxOpenPositions = inp_MaxOpenPositions; migratedModeValues = true; }
      if(MaxTradesPerMinute == 1 && inp_MaxTradesPerMinute != 1) { MaxTradesPerMinute = inp_MaxTradesPerMinute; migratedModeValues = true; }
      if(MaxDailyLossPercent == 5.0 && (inp_MaxDailyLossPercent <= 0 || inp_MaxDailyLossPercent > 5)) { MaxDailyLossPercent = inp_MaxDailyLossPercent; migratedModeValues = true; }
      if(EnableSpreadFilter && !inp_EnableSpreadFilter && MaxSpreadPoints == 30)
      {
         EnableSpreadFilter = inp_EnableSpreadFilter;
         MaxSpreadPoints = inp_MaxSpreadPoints;
         migratedModeValues = true;
      }
      else if(!EnableSpreadFilter && MaxSpreadPoints == 30 && inp_MaxSpreadPoints != 30)
      {
         MaxSpreadPoints = inp_MaxSpreadPoints;
         migratedModeValues = true;
      }
      if(migratedModeValues)
         Print("[INIT] Mode-value migration restored pre-mode limits from F7 defaults.");
   }

   if(PropFirmMode)
   {
      Print("[INIT] PropFirmMode ON - effective limits: RequireSL=true, MaxOpenPositions=", TCU_EffectiveMaxOpenPositions(),
            ", MaxDailyLossPercent=", DoubleToString(TCU_EffectiveMaxDailyLossPercent(), 2));
   }
   

   // Baseline startup state is DISARMED. The final arm state is resolved later
   // after saved settings are loaded and restart-resume rules are applied.
   ArmExecution = false;
   g_lastFilterReason = "DISARMED";

   if(migratedModeValues)
      SaveSettings();
   
   if(SignalCooldownSeconds > 0)
      g_signalCooldownRestoreMinutes = MathMax(1, SignalCooldownSeconds / 60);
   else
      g_signalCooldownRestoreMinutes = MathMax(1, inp_SignalCooldownMinutes);

   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(SlippagePoints);
   
   // Auto-detect filling mode for broker compatibility
   ENUM_ORDER_TYPE_FILLING fillMode = DetectFillMode(_Symbol);
   g_trade.SetTypeFilling(fillMode);
   Print("[INIT] Fill mode: ", EnumToString(fillMode));
   
   InitAliases();
   
   // AUTO-DETECT BROKER SUFFIX from chart symbol
   if(StringLen(SymbolSuffix) == 0)
   {
      // Try known base symbols to detect what suffix this broker uses
      string bases[] = {"EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "AUDUSD"};
      for(int b = 0; b < ArraySize(bases); b++)
      {
         string symRaw = _Symbol;
         string symUp = symRaw;
         StringToUpper(symUp);
         int bPos = StringFind(symUp, bases[b]);
         if(bPos >= 0)
         {
            g_autoSuffix = StringSubstr(symRaw, bPos + StringLen(bases[b]));
            if(StringLen(g_autoSuffix) > 0)
               Print("[INIT] Auto-detected broker suffix: '", g_autoSuffix, "' from ", _Symbol);
            break;
         }
      }
   }
   else
   {
      g_autoSuffix = SymbolSuffix;
   }
   
   if(!g_isTester)
   {
      if(EnableBotAPIMode && StringLen(TelegramBotToken) == 0)
      {
         Alert("Trade Copier: Bot API Mode requires Bot Token! Also ensure 'https://api.telegram.org' is added to Tools > Options > Expert Advisors > Allow WebRequest URLs.");
         return INIT_PARAMETERS_INCORRECT;
      }
      
      // TOKEN VALIDATION: Must contain ':', no spaces, right side > 10 chars
      if(EnableBotAPIMode && StringLen(TelegramBotToken) > 0)
      {
         if(StringFind(TelegramBotToken, ":") < 0 || StringFind(TelegramBotToken, " ") >= 0)
         {
            Alert("Trade Copier: Invalid Bot Token format! It should look like '1234567890:ABCDefGh...'. No spaces, and must contain a colon.");
            return INIT_PARAMETERS_INCORRECT;
         }
         int colonPos = StringFind(TelegramBotToken, ":");
         if(StringLen(TelegramBotToken) - colonPos - 1 < 10)
         {
            Alert("Trade Copier: Bot Token seems too short. Check you copied the full token from @BotFather.");
            return INIT_PARAMETERS_INCORRECT;
         }
      }
      
      if(EnableTelegramSend && !UseSeparateSendBot && StringLen(TelegramBotToken) == 0)
      {
         Alert("Trade Copier: Telegram Sender requires Bot Token! Also ensure 'https://api.telegram.org' is added to Tools > Options > Expert Advisors > Allow WebRequest URLs.");
         return INIT_PARAMETERS_INCORRECT;
      }
      
      if(EnableTelegramSend && UseSeparateSendBot && (StringLen(SendBotToken) < 10 || StringLen(SendChatID) == 0))
      {
         Alert("Trade Copier: Separate Send Bot requires SendBotToken and SendChatID!");
         return INIT_PARAMETERS_INCORRECT;
      }
      
      // Flush old Telegram messages at startup so we never replay them
      // [v6.01 CRITICAL FIX] Mark the session-start timestamp BEFORE the flush
      // call. Even if the flush fails or returns empty (real-world failure modes
      // on fresh VPS attaches), the date-based guard in ParseTgUpdates will
      // still drop any message older than this stamp.
      g_botSessionStartTime = TimeGMT();
      if(EnableBotAPIMode)
      {
         g_botStateFileName = "TCU_BotState.dat";
         FlushOldTelegramMessages();
      }
   }
   
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   CreatePanel();
   
   // -- AUTO /getMe TEST: silent connection check on startup ------------------------------
   if(!g_isTester && EnableBotAPIMode && StringLen(TelegramBotToken) > 10)
   {
      string gm_url = TELEGRAM_URL + TelegramBotToken + "/getMe";
      char gm_post[], gm_result[];
      string gm_hdrs = "";
      int gm_res = WebRequest("GET", gm_url, gm_hdrs, 5000, gm_post, gm_result, gm_hdrs);
      string gm_resp = CharArrayToString(gm_result);
      if(gm_res == 200 && StringFind(gm_resp, "\"ok\"") >= 0 && StringFind(gm_resp, "true") >= 0)
         Print("[INIT] [OK] Telegram Bot API: CONNECTED -- token valid and reachable.");
      else if(gm_res == -1)
      {
         string gm_err = "[INIT] [!] Telegram WebRequest BLOCKED! Go to: Tools > Options > Expert Advisors > Allow WebRequest URLs -- add: https://api.telegram.org";
         Print(gm_err);
         Alert(gm_err);
      }
      else
         Print("[INIT] [!] Telegram /getMe returned HTTP ", gm_res, " -- check token or network.");
   }
   // Fix: Use appropriate timer interval based on active modes, not bridge-dependent
   int timerMs = 1000; // Default 1 second
   if(CopierMode != MODE_DISABLED && CopierPollMs < timerMs)
      timerMs = CopierPollMs;
   if(EnableBridgeMode && BridgePollMs < timerMs)
      timerMs = BridgePollMs;
   if(timerMs < 10) timerMs = 10; // Floor: 10ms min -- allow fast local copying
   g_timerMs = timerMs;
   EventSetMillisecondTimer(timerMs);
   // NOTE: g_lastTimerFire stays 0 -- if timer fails silently during startup,
   // the very first OnTick will catch it immediately and reinitialize.
   UpdateModeStr();
   
   if(EnableBridgeMode)
   {
      g_bridgeFailCount = 1;  // Start with backoff so first poll is deferred
      g_bridgeNextRetry = GetTickCount64() + 5000;
      Print("[Bridge] Deferred first poll by 5s to avoid startup freeze");
   }
   
   // F7 inputs cannot be edited by the EA at runtime, so use this rule:
   // unchanged F7 => restore saved canvas settings; changed F7 => F7 wins.
   string savedInputSig = TCU_LoadSavedInputSignature();
   string currentInputSig = TCU_CurrentInputSignature();
   bool restoredSettings = false;
   if(StringLen(savedInputSig) > 0 && savedInputSig != currentInputSig)
   {
      SaveSettings();
      Print("[TCU] F7 inputs changed -- using F7 values and refreshing saved canvas settings.");
   }
   else if(LoadSettings())
   {
      restoredSettings = true;
      Print("[TCU] Settings restored from previous session.");
      if(StringLen(savedInputSig) == 0)
         SaveSettings(); // seed signature for older saved profiles
   }
   else
   {
      SaveSettings();
      Print("[TCU] First launch -- using input parameter defaults.");
   }

   // -- RESTART-SAFE DEDUP: restore processed signal hashes using the resolved user window
   //    from saved settings (or fresh input defaults on first launch).
   LoadPersistedHashes();

   // [MG FIX] Pre-populate deal dedup cache so MG_SyncFromHistory won't
   // re-count deals that already built the restored streak.
   if(EnableMartingale)
      MG_InitDealCache();

   bool resumeArmedAfterRestart = false;
   string settingsPrefix = "TCU_" + IntegerToString(MagicNumber) + "_";
   string restartResumeKey = settingsPrefix + "ResumeArmOnRestart";
   // restoredSettings guard removed: F7 param changes / recompiles set restoredSettings=false
   // but OnDeinit already wrote ResumeArmOnRestart=1 (if armed). Keeping the guard silently
   // disarmed the EA on every parameter tweak. The key is only ever written by OnDeinit so
   // it cannot fire on a true first-launch where it doesn't exist yet.
   if(!DisarmOnRestart && GlobalVariableCheck(restartResumeKey))
   {
      double marker = GlobalVariableGet(restartResumeKey);
      GlobalVariableDel(restartResumeKey);
      if(marker > 0.5 && GlobalVariableCheck(settingsPrefix + "SavedArmState"))
         resumeArmedAfterRestart = GlobalVariableGet(settingsPrefix + "SavedArmState") > 0.5;
   }

   ArmExecution = resumeArmedAfterRestart;
   g_lastFilterReason = ArmExecution ? "" : "DISARMED";
   if(ArmExecution)
   {
      Print("[INIT] Restart resume: restoring ARMED state after MT5 close/reopen.");
      Print("[INIT] [OK] EA is ARMED -- live trading enabled.");
   }
   else
   {
      if(DisarmOnRestart)
         Print("[INIT] Safety reset: MT5 restart disarms EA. Rearm manually from the panel when ready.");
      else
         Print("[INIT] Safety reset: fresh attach/no close marker -- staying DISARMED. Only MT5 close/reopen can restore ARM.");
      Print("[INIT] [!] EA is DISARMED -- signals will be received and parsed but NO trades will be placed.");
      Print("[INIT] [!] Set ArmExecution=true to enable live trading.");
   }

   // [v6.3 FIX] Martingale restart-safe restore — same pattern as ArmExecution.
   // Key is ONLY written by OnDeinit (legitimate MT5 close/reopen).
   // Fresh chart attach has no key → Martingale reset to OFF regardless of saved state.
   {
      string mgResumeKey = settingsPrefix + "ResumeMartingaleOnRestart";
      if(GlobalVariableCheck(mgResumeKey))
      {
         double _mgMarker = GlobalVariableGet(mgResumeKey);
         GlobalVariableDel(mgResumeKey);
         if(_mgMarker < 0.5 && EnableMartingale)
         {
            Print("[MG][SAFETY] Martingale was ON in global vars but OFF at last deinit -- reset to OFF.");
            EnableMartingale = false;
            TCU_CommitSettings();
         }
         else if(EnableMartingale)
            Print("[MG][WARNING] *** MARTINGALE RESTORED (MT5 restart) -- active from previous session ***");
      }
      else if(EnableMartingale)
      {
         Print("[MG][SAFETY] Martingale ON in saved state but fresh attach detected -- reset to OFF.");
         Print("[MG][SAFETY] Re-enable from the Martingale tab if you want it active.");
         EnableMartingale = false;
         TCU_CommitSettings();
      }
   }

   if(!g_isTester)
   {
      if(EnableTelegramSend) ArmTelegramSenderFresh();
      if(EnableDiscordMode) ArmDiscordSenderFresh();
   }

   if(TCU_NormalizeTPExecutionModes())
      SaveSettings();
   if(TCU_NormalizeLotMode())
      SaveSettings();

   if(EnableNewsPause)
      TCU_LoadNewsCalendar();



   // -- STARTUP SUMMARY --------------------------------------------------------------------
   string srcSummary = "none";
   if(EnableBridgeMode && EnableBotAPIMode)  srcSummary = "Bridge + BotAPI";
   else if(EnableBridgeMode)                 srcSummary = "Bridge :" + IntegerToString(BridgePort);
   else if(EnableBotAPIMode)                 srcSummary = "Telegram BotAPI";
   else if(CopierMode != MODE_DISABLED)      srcSummary = "Local Copier (" + EnumToString(CopierMode) + ")";
   else if(EnableDiscordMode)                srcSummary = "Discord Sender";
   string armSummary    = ArmExecution ? "ARMED -- live trades ON" : "DISARMED -- no trades";
   string propSummary   = PropFirmMode     ? " | PROP mode" : "";
   Print("=======================================");
   // [v6.00 FIX 2026-04-26] Bumped startup banner v5.12 -> v6.00.
    Print("  TCU v6.3 -- Ready");
   Print("  Source  : ", srcSummary);
   Print("  Execute : ", armSummary, propSummary);
   Print("  Dedup   : ", EnableDuplicateFilter ? ("ON (" + IntegerToString(DuplicateWindowMinutes) + "m window, restart-safe)") : "OFF");
   Print("  Pending : ", EnablePendingOrders ? "ON" : "OFF");
   Print("  Magic#  : ", MagicNumber);
   Print("  Cooldown : ", SignalCooldownSeconds, "s | Dedup:", EnableDuplicateFilter ? ("ON " + IntegerToString(DuplicateWindowMinutes) + "m") : "OFF", " | DiagLog:", EnableDiagLog ? "ON" : "OFF");
   // [v6.00 NEW][PerSymbolLots] Validate per-symbol lots at startup. Logs typos / non-MarketWatch entries once.
   if(StringLen(PerSymbolLots) > 0)
   {
      int activeOverrides = PerSymbolLots_ValidateAndCount(true);
      Print("  Per-Sym Lots: ", activeOverrides, " active override(s) -- \"", PerSymbolLots, "\"");
   }
   Print("=======================================");

   // Open diagnostic log file
   if(EnableDiagLog && !g_isTester)
   {
      // Append mode: try opening existing file first, then create new if it doesn't exist
      g_diagFile = FileOpen(DiagLogFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(g_diagFile == INVALID_HANDLE)
         g_diagFile = FileOpen(DiagLogFileName, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON); // create new
      if(g_diagFile == INVALID_HANDLE)
         Print("[DIAG] Could not open log file: ", DiagLogFileName, " err=", GetLastError());
      else
      {
         FileSeek(g_diagFile, 0, SEEK_END); // always append -- never wipe previous sessions
         FileWriteString(g_diagFile, "\r\n=== SESSION: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " ==="
                        + "\r\nSource=" + srcSummary + " | Arm=" + armSummary
                        + " | Cooldown=" + IntegerToString(SignalCooldownSeconds) + "s"
                        + " | DupFilter=" + (EnableDuplicateFilter ? ("ON " + IntegerToString(DuplicateWindowMinutes) + "m") : "OFF")
                        + " | MinPips=" + DoubleToString(MinPipsDistanceSameType,1)
                        + " | SpreadFilter=" + (EnableSpreadFilter ? "ON max=" + IntegerToString(MaxSpreadPoints) + "pts" : "OFF")
                        + "\r\n============================================================\r\n");
         FileFlush(g_diagFile);
         Print("[DIAG] Logging to: ", DiagLogFileName, " (Common/Files folder)");
      }
   }
   // FIRST-RUN WELCOME: Guide new users who haven't configured anything
   if(!EnableBotAPIMode && !EnableBridgeMode && CopierMode == MODE_DISABLED)
   {
      Print("===================================================");
      Print("[TCU] Welcome to Trade Copier Ultimate!");
      Print("[TCU] ");
      Print("[TCU] QUICK SETUP (4 steps):");
      Print("[TCU] 1. Open EA settings > QUICK START section");
      Print("[TCU] 2. Enable Bot API Mode = true");
      Print("[TCU] 3. Paste your Bot Token from @BotFather");
      Print("[TCU] 4. Set your Chat ID (message @userinfobot on Telegram)");
      Print("[TCU] ");
      Print("[TCU] IMPORTANT: Also add this to MT5 WebRequest URLs:");
      Print("[TCU]   Tools > Options > Expert Advisors > Allow WebRequest");
      Print("[TCU]   Add: https://api.telegram.org");
      Print("[TCU] ");
      Print("[TCU] Docs: https://www.mql5.com/en/blogs/post/767362");
      Print("===================================================");
   }
   
   // Initialize report file
   if(EnableReportLog)
   {
      g_reportFileName = "TCU_Report_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
      Print("[REPORT] Report file: ", g_reportFileName);
      PurgeReport();  // Clean old entries on startup
   }
   
   if(CopierMode != MODE_DISABLED)
   {
      // Set state file name unique per copier instance to avoid cross-EA collisions
      // [v6.01 FIX] Include account login in state filename. State file lives in
      // FILE_COMMON which is shared across all MT5 terminals on the PC -- two
      // slave terminals using the same MagicNumber + CopierFileName would
      // otherwise overwrite each other's ticket maps and mass-close on restart.
      long acctLogin = AccountInfoInteger(ACCOUNT_LOGIN);
      g_stateFileName = "TCU_State_" + IntegerToString(acctLogin) + "_" +
                        IntegerToString(MagicNumber) + "_" + CopierFileName;
      StringReplace(g_stateFileName, ".csv", ".dat");
      
      // Load saved state to prevent re-copying after restart
      if(CopierMode == MODE_SLAVE)
      {
         // Clear all tracking arrays for a fresh start.
         // The initial sync (first scan) will register all existing CSV trades
         // without copying them. Only NEW trades in subsequent scans get copied.
         // This is the only reliable way to prevent copying old/stale trades.
         ArrayResize(g_copiedTickets, 0);
         ArrayResize(g_masterTicketMap, 0);
         ArrayResize(g_slaveTickets, 0);
         ArrayResize(g_masterLots, 0);
         g_initialSyncDone = (CopierStartupCopyMode == COPY_ALL_EXISTING_TRADES);
         g_initialSyncEmptyReadableScans = 0;
         g_initialSyncSnapshotCount = -1;
         g_initialSyncSnapshotHash = 0;
         g_slaveActivationGuardUntil = (CopierStartupCopyMode == COPY_NEW_TRADES_ONLY)
                                       ? GetTickCount64() + (ulong)g_slaveActivationGuardMs
                                       : 0;
         
         // Load saved state so we don't start totally fresh after a restart
         if(CopierStartupCopyMode == COPY_NEW_TRADES_ONLY)
            LoadSlaveState();
         
         Print("[SLAVE] Slave mode initialized - startup mode=", EnumToString(CopierStartupCopyMode),
               " activation guard=", (CopierStartupCopyMode == COPY_NEW_TRADES_ONLY ? g_slaveActivationGuardMs : 0),
               "ms - total tracked trades from previous session: ", ArraySize(g_masterTicketMap));
      }
      else if(CopierMode == MODE_MASTER)
      {
         TCU_MasterActivate();
      }
      
      string commonPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
      string fullPath = commonPath + "\\Files\\" + CopierFileName;
      Print("[COPIER] ============================================");
      Print("[COPIER] Common folder: ", commonPath);
      Print("[COPIER] Full file path: ", fullPath);
      Print("[COPIER] Auto-close: ", CopierAutoClose);
      Print("[COPIER] Poll speed: ", CopierPollMs, "ms");
      Print("[COPIER] ============================================");
      Print("[COPIER] IMPORTANT: Both Master and Slave MUST show");
      Print("[COPIER] the SAME 'Full file path' above!");
      Print("[COPIER] ============================================");
   }
   
    Print("TRADE COPIER ULTIMATE v6.3 initialized");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   string settingsPrefix = "TCU_" + IntegerToString(MagicNumber) + "_";
   string restartResumeKey = settingsPrefix + "ResumeArmOnRestart";
   // Persist armed state before deinit so OnInit can restore it accurately
   GlobalVariableSet(settingsPrefix + "SavedArmState", ArmExecution ? 1 : 0);
   // When DisarmOnRestart=false: preserve arm state for ANY restart reason
   // (chart timeframe change, recompile, F7 params, reconnect, etc.) not just REASON_CLOSE.
   // When DisarmOnRestart=true: always clear so OnInit comes back disarmed.
   if(!DisarmOnRestart && ArmExecution)
      GlobalVariableSet(restartResumeKey, 1);
   else
      GlobalVariableDel(restartResumeKey);

   // [v6.3 FIX] Write Martingale resume key so OnInit knows it's a legitimate restart
   {
      string mgResumeKey = settingsPrefix + "ResumeMartingaleOnRestart";
      GlobalVariableSet(mgResumeKey, EnableMartingale ? 1 : 0);
   }

   TCU_FlushActiveEdit();
   if(g_tcuSettingsDirty)
   {
      SaveSettings();
      g_tcuSettingsDirty = false;
   }
   _ScDeleteAll(); // Clean up settings panel
   TCU_DestroyCanvas();

   if(CopierMode == MODE_SLAVE) SaveSlaveState();
   EventKillTimer();
   ObjectsDeleteAll(0, PREFIX);
   if(g_diagFile != INVALID_HANDLE)
   {
      FileWriteString(g_diagFile, "\r\n=== TCU DiagLog Ended: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " ===\r\n");
      FileClose(g_diagFile);
      g_diagFile = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(TCU_HandleEditEvent(id, sparam)) return;
   // --- Style-C Panel Event Handler ---
   if(_ScEvent(id, lparam, dparam, sparam)) return;
   if(TCU_HandleCanvasEvent(id, lparam, dparam, sparam)) return;
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PREFIX+"BTN_MIN")
   {
      g_minimized = !g_minimized;
      SetMinimized(g_minimized);
      ObjectSetInteger(0, PREFIX+"BTN_MIN", OBJPROP_STATE, false);
      ChartRedraw();
   }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PREFIX+"BTN_TEST")
   {
      ObjectSetInteger(0, PREFIX+"BTN_TEST", OBJPROP_STATE, false);
      TCU_RunConnectionTest();
      ChartRedraw();
   }
   if(!g_tcuCanvasCreated && id == CHARTEVENT_MOUSE_MOVE)
   {
      int mx = (int)lparam, my = (int)dparam;
      bool lBtn = ((uint)sparam & 1) != 0;
      if(lBtn && !g_dragging && mx >= g_panelX && mx <= g_panelX+g_panelW && my >= g_panelY && my <= g_panelY+28)
      { g_dragging = true; g_dragOffsetX = mx - g_panelX; g_dragOffsetY = my - g_panelY; ChartSetInteger(0, CHART_MOUSE_SCROLL, false); }
      else if(lBtn && g_dragging) MovePanel(mx - g_dragOffsetX, my - g_dragOffsetY);
      else if(!lBtn && g_dragging) { g_dragging = false; ChartSetInteger(0, CHART_MOUSE_SCROLL, true); }
   }
}

//+------------------------------------------------------------------+
void OnTimer()
{
   ulong now = GetTickCount64();
   g_lastTimerFire = now;  // Timer is alive

   if(g_tcuSettingsDirty && now - g_tcuSettingsDirtyAt >= 250)
   {
      SaveSettings();
      g_tcuSettingsDirty = false;
   }
   
   // ===== HIGHEST PRIORITY: Local Trade Copier (no WebRequest, no blocking) =====
   // ALWAYS runs on EVERY timer tick -- never blocked by WebRequest
   
   // Local Trade Copier - Slave (configurable speed, default 50ms)
   if(CopierMode == MODE_SLAVE && now - g_lastFileScan >= (ulong)CopierPollMs)
   {
      ScanCopierFile();
      g_lastFileScan = now;
   }
   
   // Local Trade Copier - Master (configurable speed, default 50ms)
   if(CopierMode == MODE_MASTER && now - g_lastFileScan >= (ulong)CopierPollMs)
   {
      WriteMasterTrades();
      g_lastFileScan = now;
   }

   // If the slave is confirming a valid empty master file, prioritize those
   // next few reads. WebRequest/panel work below can block the timer thread
   // and make master-close sync feel slower than the lightweight Simple EA.
   if(CopierMode == MODE_SLAVE &&
      CopierAutoClose &&
      g_emptyReadCount > 0 &&
      ArraySize(g_masterTicketMap) > 0)
   {
      return;
   }
   
   // ===== LOWER PRIORITY: WebRequest-based modes =====
   // Copier already ran above (non-blocking). WebRequest calls below have
   // their own interval guards so they won't fire every tick.
   if(!g_isTester)
   {
      ProcessPendingSLTPAttaches();

      // Drain Telegram send queue (1 message per timer tick)
      if(g_tgQueueSize > 0)
      {
         bool tgSent = SendTgMsg(g_tgQueue[0]);
         if(tgSent || (ArraySize(g_tgQueueRetries) > 0 && g_tgQueueRetries[0] >= 3))
         {
            if(!tgSent) Print("[TG] Dropping queued message after 3 failed send attempts.");
            for(int q = 0; q < g_tgQueueSize - 1; q++)
            {
               g_tgQueue[q] = g_tgQueue[q + 1];
               if(q + 1 < ArraySize(g_tgQueueRetries)) g_tgQueueRetries[q] = g_tgQueueRetries[q + 1];
            }
            g_tgQueueSize--;
            ArrayResize(g_tgQueue, g_tgQueueSize);
            ArrayResize(g_tgQueueRetries, g_tgQueueSize);
         }
         else
         {
            if(ArraySize(g_tgQueueRetries) < g_tgQueueSize) ArrayResize(g_tgQueueRetries, g_tgQueueSize);
            g_tgQueueRetries[0]++;
         }
      }
      if(g_dcQueueSize > 0)
      {
         bool dcSent = SendDiscordMsg(g_dcQueue[0]);
         if(dcSent || (ArraySize(g_dcQueueRetries) > 0 && g_dcQueueRetries[0] >= 3))
         {
            if(!dcSent) Print("[DISCORD] Dropping queued message after 3 failed send attempts.");
            for(int qd = 0; qd < g_dcQueueSize - 1; qd++)
            {
               g_dcQueue[qd] = g_dcQueue[qd + 1];
               if(qd + 1 < ArraySize(g_dcQueueRetries)) g_dcQueueRetries[qd] = g_dcQueueRetries[qd + 1];
            }
            g_dcQueueSize--;
            ArrayResize(g_dcQueue, g_dcQueueSize);
            ArrayResize(g_dcQueueRetries, g_dcQueueSize);
         }
         else
         {
            if(ArraySize(g_dcQueueRetries) < g_dcQueueSize) ArrayResize(g_dcQueueRetries, g_dcQueueSize);
            g_dcQueueRetries[0]++;
         }
      }
      
      // Bot API Mode FIRST (Telegram polling) -- with exponential backoff on errors
      // Runs BEFORE bridge to ensure Bot API is never blocked by bridge WebRequest
      {
         ulong tgInterval = (ulong)TelegramPollSeconds * 1000;
         if(g_telegramFailCount > 3) tgInterval = MathMin(tgInterval * (ulong)g_telegramFailCount, 30000); // Max 30s backoff
         if(EnableBotAPIMode && now - g_lastTelegramPoll >= tgInterval)
         {
            PollTelegram();
            g_lastTelegramPoll = now;
         }
      }
      
      // Bridge Mode LAST -- enforce minimum 1s poll interval
      ulong bridgeInterval = (ulong)BridgePollMs;
      if(bridgeInterval < 1000) bridgeInterval = 1000;
      if(EnableBridgeMode && now - g_lastBridgePoll >= bridgeInterval)
      {
         PollBridge();
         g_lastBridgePoll = now;
      }
   }
   
   // Heartbeat log every 30 seconds (reduced spam)
   static ulong lastHeartbeat = 0;
   if(now - lastHeartbeat >= 30000)
   {
      Print("[TIMER] Heartbeat | Copier=", EnumToString(CopierMode), 
            " Bridge=", EnableBridgeMode, " BotAPI=", EnableBotAPIMode,
            " DiscordSend=", EnableDiscordMode,
            " TgQueue=", g_tgQueueSize, " DcQueue=", g_dcQueueSize);
      lastHeartbeat = now;
   }

   // Bridge heartbeat → lets the Bridge auto-detect broker suffix and
   // register this MT5 on the Accounts page.
   // First heartbeat fires immediately (so the Bridge UI sees us fast),
   // then once per 60s thereafter.
   static ulong lastBridgeHb = 0;
   if(!g_isTester && EnableBridgeMode &&
      (lastBridgeHb == 0 || now - lastBridgeHb >= 60000))
   {
      SendBridgeHeartbeat();
      lastBridgeHb = now;
   }

   static ulong lastNewsRefresh = 0;
   if(EnableNewsPause && now - lastNewsRefresh >= 1800000)
   {
      TCU_LoadNewsCalendar();
      lastNewsRefresh = now;
   }
   
   // Update panel every 500ms + trailing stop management
   static ulong lastPanel = 0;
   if(now - lastPanel >= 500)
   {
      UpdatePanel();
      if(EnableTrailingStop && !EnableMartingale) ManageTrailingStop();
       if(EnablePartialClose && !EnableMartingale && g_partialCount > 0) ManagePartialClose();
       if(EnableMultiTP     && !EnableMartingale && g_mtpCount > 0) ManageMultiTP();
      if(EnablePendingExpiry) ManagePendingExpiry();
      lastPanel = now;
   }
   
   // Purge old report entries every hour
   static ulong lastPurge = 0;
   if(EnableReportLog && now - lastPurge >= 3600000)
   {
      PurgeReport();
      lastPurge = now;
   }

   static ulong lastMonitorDraw = 0;
   if(g_tcuMonOpen && now - lastMonitorDraw >= 700)
   {
      lastMonitorDraw = now;
      TCU_DrawMonitorPopup();
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   if((EnableTelegramSend || EnableDiscordMode) && !g_isTester) QueueNewTrades();
   
   // MQL5 Market validation: open on first tick, close on second tick.
   // This satisfies "there are no trading operations" without risking stop-out.
   static int testerState = 0; // 0=Init, 1=WaitingForOpen, 2=WaitingForClose, 3=Done
   if(g_isTester && testerState < 3)
   {
      string sym = _Symbol;
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(ask == 0) return;
      
      if(testerState == 2)
      {
         if(PositionSelectByTicket(g_testerTicket))
         {
            if(g_trade.PositionClose(g_testerTicket))
            {
               Print("[TESTER] Validation trade closed properly");
               testerState = 3;
            }
         }
         else
         {
            // Position disappeared (maybe stopped out), count as done
            testerState = 3;
         }
      }
      else if(testerState == 0)
      {
         testerState = 1; // Mark as attempting to open
         double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
         if(ask > 0 && minLot > 0)
         {
            // Pre-check margin to avoid "not enough money" error in validator
            double marginRequired = 0;
            if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, minLot, ask, marginRequired))
            {
               Print("[TESTER] Cannot calculate margin for ", sym, ", skipping validation trade");
               testerState = 0; // Reset
               return;
            }
            double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
            if(freeMargin < marginRequired)
            {
               Print("[TESTER] Insufficient margin (", freeMargin, " < ", marginRequired, "), skipping validation trade");
               testerState = 0; // Reset
               return;
            }
            g_trade.SetExpertMagicNumber(MagicNumber);
            g_trade.SetTypeFilling(DetectFillMode(sym));
            g_trade.SetDeviationInPoints(SlippagePoints);
    if(g_trade.Buy(minLot, sym, ask, 0, 0, TCU_TradeComment("TCU_VALIDATION")))
            {
               g_testerTicket = g_trade.ResultOrder();
               Print("[TESTER] Validation trade opened: ", sym, " ticket=", g_testerTicket);
               testerState = 2; // Move to closing state
            }
            else
            {
               testerState = 0; // Try again next tick
            }
         }
      }
      return;
   }
   
   // SAFETY: If timer hasn't fired since startup (g_lastTimerFire==0) or in 5+ seconds,
   // it probably failed during startup -- reinitialize and run copier directly
   ulong now = GetTickCount64();
   if(!g_isTester && (g_lastTimerFire == 0 || now - g_lastTimerFire > 5000))
   {
      Print("[SAFETY] Timer not firing -- reinitializing (", g_timerMs, "ms)");
      EventKillTimer();  // Kill any broken timer first
      EventSetMillisecondTimer(g_timerMs);
      g_lastTimerFire = now;
   }
   
   // Copier fallback: also scan from OnTick if copier mode is active
   // This ensures trades are copied even if OnTimer isn't firing
   if(CopierMode == MODE_SLAVE && now - g_lastFileScan >= (ulong)CopierPollMs)
   {
      ScanCopierFile();
      g_lastFileScan = now;
   }
}

//+------------------------------------------------------------------+
void OnTrade()
{
   // Some brokers/builds do not emit the transaction type we expect for every
   // position-list or SL/TP change. Keep this lightweight fallback so the local
   // copier CSV is refreshed as soon as MT5 tells us "trade state changed".
   if(CopierMode == MODE_MASTER)
   {
      static ulong lastOnTradeMasterWrite = 0;
      ulong now = GetTickCount64();
      if(now - lastOnTradeMasterWrite >= 20)
      {
         Print("[MASTER] OnTrade fired - writing CSV");
         WriteMasterTrades();
         g_lastFileScan = now;
         lastOnTradeMasterWrite = now;
      }
   }
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Master: immediately write CSV when any trade event occurs
   // This is far more reliable than waiting for OnTimer which can stop firing
   if(CopierMode == MODE_MASTER)
   {
      // React to deals and position updates. SL/TP edits usually arrive as
      // TRADE_TRANSACTION_POSITION, so write immediately instead of waiting.
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
         trans.type == TRADE_TRANSACTION_HISTORY_ADD ||
         trans.type == TRADE_TRANSACTION_POSITION)
      {
         Print("[MASTER] Trade event detected (", EnumToString(trans.type), ") - writing CSV immediately");
         WriteMasterTrades();
         g_lastFileScan = GetTickCount64();
      }
   }

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
   {
      if(HistoryDealSelect(trans.deal))
      {
         long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         {
            g_dailyLossCacheInvalidAfter = TimeCurrent();
            // Notify bridge so it can mark this ticket as closed in its DB.
            // DEAL_POSITION_ID is the position ticket that was closed.
            if(EnableBridgeMode && !g_isTester)
            {
               ulong closedPosTicket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
               string closedSym     = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
               if(closedPosTicket > 0)
                  SendBridgeCallback("", IntegerToString(closedPosTicket), "CLOSED", closedSym);
            }
            // [MARTINGALE] Track close result
            if(EnableMartingale)
            {
               long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
               if(dealMagic == MagicNumber || dealMagic == 0 || MagicNumber == 0)
               {
                  // Guard: OnTradeTransaction can fire multiple times for the same deal
                  // on some brokers -- skip if we already processed this deal ticket.
                  if(!MG_IsDealProcessed(trans.deal))
                  {
                     MG_MarkDealProcessed(trans.deal);
                     string dealSym  = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
                     double dealRaw  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                     double dealProfit = dealRaw
                                       + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                                       + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
                     // Detect partial close: position still exists after the deal
                     ulong dealPosId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
                     bool isPartial  = PositionSelectByTicket(dealPosId);
                     MG_OnClose(dealSym, dealProfit, true, isPartial, dealRaw);
                     TCU_CommitSettings(); // persist updated streak immediately
                     TCU_DrawUI(); // refresh tab to show updated streak
                  }
               }
            }
         }
      }
   }
   
   // Telegram sender: queue alert on new deals
   if((EnableTelegramSend || EnableDiscordMode) && !g_isTester && trans.type == TRADE_TRANSACTION_DEAL_ADD)
      QueueNewTrades();
}

//+------------------------------------------------------------------+
// REPORT LOG: Append a timestamped entry to the report file
//+------------------------------------------------------------------+
void WriteReport(string action, string symbol, string direction, double lots, 
                 ulong masterTicket, ulong slaveTicket, string details)
{
   if(!EnableReportLog) return;
   if(StringLen(g_reportFileName) == 0) return;
   
   // Check if file exists and has content
   bool needHeader = !FileIsExist(g_reportFileName, FILE_COMMON);
   
   int h = FileOpen(g_reportFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   
   // Seek to end of file for append
   FileSeek(h, 0, SEEK_END);
   
   // Write header if new file
   if(needHeader)
      FileWriteString(h, "Time,Action,Symbol,Direction,Lots,MasterTicket,SlaveTicket,Details\n");
   
   string line = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "," +
                 action + "," + symbol + "," + direction + "," +
                 DoubleToString(lots, 2) + "," +
                 IntegerToString((long)masterTicket) + "," +
                 IntegerToString((long)slaveTicket) + "," +
                 details + "\n";
   FileWriteString(h, line);
   FileClose(h);
}

//+------------------------------------------------------------------+
// REPORT PURGE: Remove entries older than ReportPurgeDays
//+------------------------------------------------------------------+
void PurgeReport()
{
   if(!EnableReportLog) return;
   if(StringLen(g_reportFileName) == 0) return;
   if(ReportPurgeDays <= 0) return;
   if(!FileIsExist(g_reportFileName, FILE_COMMON)) return;
   
   int h = FileOpen(g_reportFileName, FILE_READ|FILE_TXT|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   
   datetime cutoff = (datetime)(TimeCurrent() - (long)ReportPurgeDays * 86400);
   
   // Read all lines
   string kept[];
   int keptCount = 0;
   bool firstLine = true;
   
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) == 0) continue;
      
      if(firstLine)
      {
         firstLine = false;
         continue; // Skip header
      }
      
      // Parse time from start of line (before first comma)
      int commaPos = StringFind(line, ",");
      if(commaPos <= 0) continue;
      string timeStr = StringSubstr(line, 0, commaPos);
      datetime lineTime = StringToTime(timeStr);
      if(lineTime >= cutoff)
      {
         ArrayResize(kept, keptCount + 1);
         kept[keptCount] = line;
         keptCount++;
      }
   }
   FileClose(h);
   
   // Rewrite file with only recent entries
   h = FileOpen(g_reportFileName, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   
   FileWriteString(h, "Time,Action,Symbol,Direction,Lots,MasterTicket,SlaveTicket,Details\n");
   for(int i = 0; i < keptCount; i++)
      FileWriteString(h, kept[i] + "\n");
   FileClose(h);
   
   Print("[REPORT] Purge complete, kept ", keptCount, " recent records");
}

//+------------------------------------------------------------------+
void InitAliases()
{
   AddAlias("GOLD", "XAUUSD");
   AddAlias("SILVER", "XAGUSD");
   AddAlias("EURO", "EURUSD");
   AddAlias("CABLE", "GBPUSD");
   AddAlias("FIBER", "EURUSD");
   AddAlias("GOPHER", "USDJPY");
   AddAlias("KIWI", "NZDUSD");
   AddAlias("AUSSIE", "AUDUSD");
   AddAlias("LOONIE", "USDCAD");
   AddAlias("SWISSIE", "USDCHF");
   AddAlias("US30", "US30");
   AddAlias("DOW", "US30");
   AddAlias("DOWJONES", "US30");
   AddAlias("DJ30", "US30");
   AddAlias("NAS", "NAS100");
   AddAlias("NASDAQ", "NAS100");
   AddAlias("USTEC", "NAS100");
   AddAlias("SPX", "SPX500");
   AddAlias("SP500", "SPX500");
   AddAlias("BITCOIN", "BTCUSD");
   AddAlias("BTC", "BTCUSD");
   AddAlias("ETH", "ETHUSD");
   AddAlias("ETHEREUM", "ETHUSD");
   
   if(StringLen(CustomMappings) > 0)
   {
      string pairs[];
      int cnt = StringSplit(CustomMappings, ',', pairs);
      for(int i = 0; i < cnt; i++)
      {
         string parts[];
         if(StringSplit(pairs[i], '=', parts) == 2)
         {
            StringTrimLeft(parts[0]);
            StringTrimRight(parts[0]);
            StringTrimLeft(parts[1]);
            StringTrimRight(parts[1]);
            AddAlias(parts[0], parts[1]);
         }
      }
   }

   // v6.00: initialize the full 4-layer resolver dictionaries
   BuildSuffixList();
   BuildAliasDictionary();
}

//+------------------------------------------------------------------+
void AddAlias(string alias, string sym)
{
   ArrayResize(g_aliasNames, g_aliasCount + 1);
   ArrayResize(g_aliasSymbols, g_aliasCount + 1);
   StringToUpper(alias);
   g_aliasNames[g_aliasCount] = alias;
   g_aliasSymbols[g_aliasCount] = sym;
   g_aliasCount++;
}

//+------------------------------------------------------------------+
bool SymbolOK(string sym)
{
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   return (bid > 0);
}

//+==================================================================+
//| 4-LAYER SYMBOL RESOLVER (v6.00)                                   |
//|   L1: Direct match   -- SymbolExists(inp)                         |
//|   L2: Suffix mutation -- add/strip/strip-then-add + slash removal |
//|   L3: Alias dictionary (bidirectional, with suffix mutations)     |
//|   L4: MarketWatch scan with scoring (prefers visible + shorter)   |
//|   Cache: Negative AND positive results cached in g_mapCache*      |
//+==================================================================+

// ---------- Suffix / Alias registration helpers -------------------
void AddSfx(string s)
{
   if(StringLen(s) == 0) return;
   for(int i = 0; i < g_sfxCount; i++) if(g_sfxList[i] == s) return; // dedupe
   ArrayResize(g_sfxList, g_sfxCount + 1);
   g_sfxList[g_sfxCount] = s;
   g_sfxCount++;
}

void AddAliasPair(string a, string b)
{
   if(StringLen(a) == 0 || StringLen(b) == 0 || a == b) return;
   StringToUpper(a); StringToUpper(b);
   ArrayResize(g_naliasA, g_naliasCount + 1);
   ArrayResize(g_naliasB, g_naliasCount + 1);
   g_naliasA[g_naliasCount] = a;
   g_naliasB[g_naliasCount] = b;
   g_naliasCount++;
}

// ---------- Symbol existence and exact-case lookup ----------------
bool SymbolExists(string sym)
{
   // Fast path: broker's own existence flag
   long val = 0;
   if(SymbolInfoInteger(sym, SYMBOL_EXIST, val) && val != 0) return true;

   // Fallback: case-insensitive scan across full broker symbol list
   int total = SymbolsTotal(false);
   string symU = sym; StringToUpper(symU);
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      if(name == "") continue;
      string nameU = name; StringToUpper(nameU);
      if(nameU == symU) return true;
   }
   return false;
}

string GetExactCaseName(string sym)
{
   int total = SymbolsTotal(false);
   string symU = sym; StringToUpper(symU);
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      if(name == "") continue;
      string nameU = name; StringToUpper(nameU);
      if(nameU == symU)
      {
         SymbolSelect(name, true);
         return name;
      }
   }
   // Fallback: try select as-is and return it
   SymbolSelect(sym, true);
   return sym;
}

// ---------- Core extraction (strip prefixes and all suffixes) -----
string ExtractCore(string sym)
{
   string core = sym;
   // Strip leading special chars: # . ! +
   while(StringLen(core) > 0)
   {
      ushort ch = StringGetCharacter(core, 0);
      if(ch == '#' || ch == '.' || ch == '!' || ch == '+')
         core = StringSubstr(core, 1);
      else break;
   }
   // Iteratively strip trailing suffixes (longest-iter safety = 20)
   bool changed = true;
   int iter = 20;
   while(changed && iter-- > 0)
   {
      changed = false;
      for(int i = 0; i < g_sfxCount; i++)
      {
         string suf = g_sfxList[i]; StringToUpper(suf);
         int sufLen = StringLen(suf);
         int coreLen = StringLen(core);
         if(coreLen <= sufLen) continue;
         string tail = StringSubstr(core, coreLen - sufLen);
         if(tail == suf)
         {
            core = StringSubstr(core, 0, coreLen - sufLen);
            changed = true;
            break;
         }
      }
   }
   StringReplace(core, "/", "");
   return core;
}

int GetPossibleCores(string sym, string &cores[])
{
   ArrayFree(cores);
   int count = 0;
   string primary = ExtractCore(sym);
   if(primary != "" && primary != sym)
   {
      ArrayResize(cores, count + 1);
      cores[count++] = primary;
   }
   for(int i = 0; i < g_sfxCount; i++)
   {
      string suf = g_sfxList[i]; StringToUpper(suf);
      int sufLen = StringLen(suf);
      int symLen = StringLen(sym);
      if(symLen <= sufLen) continue;
      string tail = StringSubstr(sym, symLen - sufLen);
      if(tail == suf)
      {
         string variant = StringSubstr(sym, 0, symLen - sufLen);
         bool exists = false;
         for(int j = 0; j < count; j++) if(cores[j] == variant) { exists = true; break; }
         if(!exists)
         {
            ArrayResize(cores, count + 1);
            cores[count++] = variant;
         }
      }
   }
   return count;
}

int GetAliasEquivalents(string core, string &equiv[])
{
   ArrayFree(equiv);
   int count = 0;
   for(int i = 0; i < g_naliasCount; i++)
   {
      if(g_naliasA[i] == core)
      {
         ArrayResize(equiv, count + 1);
         equiv[count++] = g_naliasB[i];
      }
      else if(g_naliasB[i] == core)
      {
         ArrayResize(equiv, count + 1);
         equiv[count++] = g_naliasA[i];
      }
   }
   return count;
}

// ---------- Layer implementations ---------------------------------
string TryDirect(string sym)
{
   if(SymbolExists(sym)) return GetExactCaseName(sym);
   return "";
}

string TrySuffixMutation(string sym)
{
   // Phase A: strip suffixes from incoming
   for(int i = 0; i < g_sfxCount; i++)
   {
      string suf = g_sfxList[i]; StringToUpper(suf);
      int sufLen = StringLen(suf);
      int symLen = StringLen(sym);
      if(symLen <= sufLen) continue;
      string tail = StringSubstr(sym, symLen - sufLen);
      if(tail == suf)
      {
         string core = StringSubstr(sym, 0, symLen - sufLen);
         if(StringLen(core) > 0 && SymbolExists(core))
            return GetExactCaseName(core);
      }
   }
   // Phase B: add suffixes
   for(int i = 0; i < g_sfxCount; i++)
   {
      string candidate = sym + g_sfxList[i];
      if(SymbolExists(candidate)) return GetExactCaseName(candidate);
   }
   // Phase C: strip one suffix, add another
   for(int i = 0; i < g_sfxCount; i++)
   {
      string suf = g_sfxList[i]; StringToUpper(suf);
      int sufLen = StringLen(suf);
      int symLen = StringLen(sym);
      if(symLen <= sufLen) continue;
      string tail = StringSubstr(sym, symLen - sufLen);
      if(tail == suf)
      {
         string core = StringSubstr(sym, 0, symLen - sufLen);
         if(StringLen(core) == 0) continue;
         for(int j = 0; j < g_sfxCount; j++)
         {
            if(j == i) continue;
            string candidate = core + g_sfxList[j];
            if(SymbolExists(candidate)) return GetExactCaseName(candidate);
         }
      }
   }
   // Also handle slash notation: XAU/USD -> XAUUSD
   if(StringFind(sym, "/") >= 0)
   {
      string noSlash = sym;
      StringReplace(noSlash, "/", "");
      if(SymbolExists(noSlash)) return GetExactCaseName(noSlash);
      for(int i = 0; i < g_sfxCount; i++)
      {
         string candidate = noSlash + g_sfxList[i];
         if(SymbolExists(candidate)) return GetExactCaseName(candidate);
      }
   }
   return "";
}

string TryAliasDictionary(string sym)
{
   string cores[];
   int coreCount = GetPossibleCores(sym, cores);
   int total = coreCount + 1;
   string lookups[];
   ArrayResize(lookups, total);
   lookups[0] = sym;
   for(int i = 0; i < coreCount; i++) lookups[i + 1] = cores[i];

   for(int c = 0; c < total; c++)
   {
      string lookup = lookups[c];
      for(int i = 0; i < g_naliasCount; i++)
      {
         string target = "";
         if(g_naliasA[i] == lookup)      target = g_naliasB[i];
         else if(g_naliasB[i] == lookup) target = g_naliasA[i];
         if(target == "") continue;
         if(SymbolExists(target)) return GetExactCaseName(target);
         for(int j = 0; j < g_sfxCount; j++)
         {
            string candidate = target + g_sfxList[j];
            if(SymbolExists(candidate)) return GetExactCaseName(candidate);
         }
      }
   }
   return "";
}

string TryMarketWatchScan(string sym)
{
   string sigCore = ExtractCore(sym);
   if(StringLen(sigCore) < 3) return "";

   string equiv[];
   int equivCount = GetAliasEquivalents(sigCore, equiv);
   int searchCount = equivCount + 1;
   string searchCores[];
   ArrayResize(searchCores, searchCount);
   searchCores[0] = sigCore;
   for(int i = 0; i < equivCount; i++) searchCores[i + 1] = equiv[i];

   int total = SymbolsTotal(false);
   string bestMatch = "";
   int bestScore = 0;

   for(int s = 0; s < total; s++)
   {
      string bsym = SymbolName(s, false);
      if(bsym == "") continue;
      string bUP = bsym; StringToUpper(bUP);
      string bCore = ExtractCore(bUP);
      if(StringLen(bCore) == 0) continue;

      for(int c = 0; c < searchCount; c++)
      {
         if(bCore == searchCores[c])
         {
            bool visible = (SymbolInfoInteger(bsym, SYMBOL_VISIBLE) != 0);
            int score = 100 + (visible ? 50 : 0);
            // Prefer shorter (less suffix junk)
            score += (100 - MathMin(StringLen(bsym), 99));
            if(score > bestScore)
            {
               bestScore = score;
               bestMatch = bsym;
            }
         }
      }
   }

   if(bestMatch != "")
   {
      SymbolSelect(bestMatch, true);
      return bestMatch;
   }
   return "";
}

//+------------------------------------------------------------------+
string MapSym(string inp)
{
   StringToUpper(inp);
   StringTrimLeft(inp);
   StringTrimRight(inp);
   if(StringLen(inp) == 0) return inp;

   // --- Cache check (positive and negative results both cached) ---
   for(int mc = 0; mc < g_mapCacheCount; mc++)
   {
      if(g_mapCacheIn[mc] == inp)
      {
         if(EnableDiagLog) Print("[MapSym] cache hit: ", inp, " -> ", g_mapCacheOut[mc]);
         return g_mapCacheOut[mc];
      }
   }

   // --- Layer 0: User CustomMappings + legacy AddAlias entries override all ---
   // g_aliasNames/g_aliasSymbols holds the user's explicit overrides from
   // inp_CustomMappings. These take priority over the broad dictionary.
   for(int i = 0; i < g_aliasCount; i++)
   {
      if(inp == g_aliasNames[i])
      {
         string mapped = g_aliasSymbols[i];
         if(SymbolExists(mapped))
         {
            string exact = GetExactCaseName(mapped);
            Print("[MapSym] L0 custom: ", inp, " -> ", exact);
            return CacheMap(inp, exact);
         }
         // Try suffix mutations on the custom mapping
         string alt = TrySuffixMutation(mapped);
         if(alt != "")
         {
            Print("[MapSym] L0 custom+suffix: ", inp, " -> ", alt);
            return CacheMap(inp, alt);
         }
      }
   }

   // --- Layer 1: Direct match ---
   string r = TryDirect(inp);
   if(r != "") { Print("[MapSym] L1 direct: ", inp, " -> ", r); return CacheMap(inp, r); }

   // --- Layer 1b: User/auto suffix fast path (before full mutation scan) ---
   if(StringLen(SymbolSuffix) > 0)
   {
      string probe = inp + SymbolSuffix;
      if(SymbolExists(probe))
      {
         string e = GetExactCaseName(probe);
         Print("[MapSym] L1b user-suffix: ", inp, " -> ", e);
         return CacheMap(inp, e);
      }
   }
   if(StringLen(g_autoSuffix) > 0)
   {
      string probe = inp + g_autoSuffix;
      if(SymbolExists(probe))
      {
         string e = GetExactCaseName(probe);
         Print("[MapSym] L1b auto-suffix: ", inp, " -> ", e);
         return CacheMap(inp, e);
      }
   }

   // --- Layer 2: Suffix mutation (add / strip / strip-then-add, slashes) ---
   r = TrySuffixMutation(inp);
   if(r != "")
   {
      Print("[MapSym] L2 suffix: ", inp, " -> ", r);
      // Learn auto-suffix from a successful add
      if(StringLen(g_autoSuffix) == 0 && StringLen(r) > StringLen(inp))
         g_autoSuffix = StringSubstr(r, StringLen(inp));
      return CacheMap(inp, r);
   }

   // --- Layer 3: Alias dictionary (bidirectional + suffix mutations) ---
   r = TryAliasDictionary(inp);
   if(r != "") { Print("[MapSym] L3 alias: ", inp, " -> ", r); return CacheMap(inp, r); }

   // --- Layer 4: MarketWatch full scan with scoring ---
   r = TryMarketWatchScan(inp);
   if(r != "")
   {
      Print("[MapSym] L4 scan: ", inp, " -> ", r);
      if(StringLen(g_autoSuffix) == 0 && StringLen(r) > StringLen(inp))
         g_autoSuffix = StringSubstr(r, StringLen(inp));
      return CacheMap(inp, r);
   }

   // Nothing worked -- cache negative so we don't rescan on every signal
   Print("[MapSym] All 4 layers failed for: ", inp, " (returning input)");
   return CacheMap(inp, inp);
}

//+------------------------------------------------------------------+
//| BuildSuffixList: ~60 broker suffix variants covering ICMarkets,  |
//|   Pepperstone, FTMO, Exness, RoboForex, XM, FBS, HotForex,       |
//|   Tickmill, FxPro, Alpari, TopFX and major prop firms.           |
//+------------------------------------------------------------------+
void BuildSuffixList()
{
   g_sfxCount = 0;
   ArrayFree(g_sfxList);

   // Dot suffixes (case variants)
   AddSfx(".m");    AddSfx(".M");
   AddSfx(".ecn");  AddSfx(".ECN");
   AddSfx(".raw");  AddSfx(".RAW");
   AddSfx(".pro");  AddSfx(".PRO");
   AddSfx(".std");  AddSfx(".STD");
   AddSfx(".sb");   AddSfx(".SB");
   AddSfx(".stp");  AddSfx(".STP");
   AddSfx(".micro");AddSfx(".MICRO");
   AddSfx(".mini"); AddSfx(".MINI");
   AddSfx(".cent"); AddSfx(".CENT");
   AddSfx(".vip");  AddSfx(".VIP");
   AddSfx(".min");  AddSfx(".MIN");

   // Single-char dot
   AddSfx(".z"); AddSfx(".c"); AddSfx(".b");
   AddSfx(".e"); AddSfx(".i"); AddSfx(".r");
   AddSfx(".s"); AddSfx(".a"); AddSfx(".f");
   AddSfx(".x"); AddSfx(".k"); AddSfx(".n");
   AddSfx(".d"); AddSfx(".g"); AddSfx(".h");
   AddSfx(".j");

   // Underscore
   AddSfx("_m");    AddSfx("_i");
   AddSfx("_ecn");  AddSfx("_raw");
   AddSfx("_pro");  AddSfx("_std");
   AddSfx("_sb");   AddSfx("_SB");
   AddSfx("_micro");AddSfx("_mini");
   AddSfx("_cent"); AddSfx("_cash");

   // Single-char no-dot (EURUSDm / EURUSDc style)
   AddSfx("m");  AddSfx("c");  AddSfx("i");
   AddSfx("z");  AddSfx("b");  AddSfx("e");
   AddSfx("r");  AddSfx("s");  AddSfx("a");
   AddSfx("f");  AddSfx("x");  AddSfx("k");
   AddSfx("n");  AddSfx("d");  AddSfx("g");
   AddSfx("h");  AddSfx("j");

   // Multi-char no-separator
   AddSfx("ecn"); AddSfx("raw"); AddSfx("pro");
   AddSfx("std"); AddSfx("sb");  AddSfx("stp");
   AddSfx("micro"); AddSfx("mini"); AddSfx("cent");
   AddSfx("cash"); AddSfx("spot"); AddSfx("CASH");

   // Numeric suffixes (some brokers use these)
   AddSfx("01"); AddSfx("02"); AddSfx("03");
   AddSfx("04"); AddSfx("05");

   // Roman
   AddSfx(".ii"); AddSfx(".iii");

   // Prop firm / platform
   AddSfx(".cash"); AddSfx(".spot");
   AddSfx("+");
}

//+------------------------------------------------------------------+
//| BuildAliasDictionary: 150+ bidirectional alias pairs covering    |
//|   metals, oil/energy, US/EU/Asia indices, USDX, crypto, bonds,   |
//|   agricultural. Each AddAliasPair(A,B) matches A<->B.            |
//+------------------------------------------------------------------+
void BuildAliasDictionary()
{
   g_naliasCount = 0;
   ArrayFree(g_naliasA);
   ArrayFree(g_naliasB);

   // METALS
   AddAliasPair("GOLD",    "XAUUSD");
   AddAliasPair("XAUUSD",  "GOLDUSD");
   AddAliasPair("SILVER",  "XAGUSD");
   AddAliasPair("XAGUSD",  "SILVERUSD");
   AddAliasPair("XPTUSD",  "PLATINUM");
   AddAliasPair("XPDUSD",  "PALLADIUM");
   AddAliasPair("XAUCAD",  "GOLDCAD");
   AddAliasPair("XAUEUR",  "GOLDEUR");
   AddAliasPair("XAUAUD",  "GOLDAUD");
   AddAliasPair("XAUCHF",  "GOLDCHF");
   AddAliasPair("XAUGBP",  "GOLDGBP");
   AddAliasPair("XAUJPY",  "GOLDJPY");

   // OIL & ENERGY
   AddAliasPair("USOIL",    "WTIUSD");
   AddAliasPair("USOIL",    "USOUSD");
   AddAliasPair("USOIL",    "CL");
   AddAliasPair("WTIUSD",   "CRUDEOIL");
   AddAliasPair("WTIUSD",   "WTI");
   AddAliasPair("UKOIL",    "BRENTUSD");
   AddAliasPair("UKOIL",    "BRENT");
   AddAliasPair("BRENTUSD", "UKOUSD");
   AddAliasPair("BRENTUSD", "BCO");
   AddAliasPair("NGAS",     "NATGAS");
   AddAliasPair("NGAS",     "XNGUSD");
   AddAliasPair("NGAS",     "NATURALGAS");
   AddAliasPair("NGAS",     "NG");

   // FX NICKNAMES
   AddAliasPair("EURO",    "EURUSD");
   AddAliasPair("CABLE",   "GBPUSD");
   AddAliasPair("FIBER",   "EURUSD");
   AddAliasPair("GOPHER",  "USDJPY");
   AddAliasPair("KIWI",    "NZDUSD");
   AddAliasPair("AUSSIE",  "AUDUSD");
   AddAliasPair("LOONIE",  "USDCAD");
   AddAliasPair("SWISSIE", "USDCHF");

   // US INDICES -- Dow
   AddAliasPair("US30", "DJ30");
   AddAliasPair("US30", "DJI30");
   AddAliasPair("US30", "DOW30");
   AddAliasPair("US30", "DOWJONES");
   AddAliasPair("US30", "DOW");
   AddAliasPair("US30", "WS30");
   AddAliasPair("US30", "YM");
   AddAliasPair("US30", "USTEC30");

   // US INDICES -- S&P 500
   AddAliasPair("US500",  "SPX500");
   AddAliasPair("US500",  "SP500");
   AddAliasPair("US500",  "SPX");
   AddAliasPair("US500",  "ES");
   AddAliasPair("US500",  "SPA500");
   AddAliasPair("SPX500", "SP500");

   // US INDICES -- Nasdaq
   AddAliasPair("NAS100", "USTEC");
   AddAliasPair("NAS100", "NASDAQ");
   AddAliasPair("NAS100", "NAS");
   AddAliasPair("NAS100", "NDX100");
   AddAliasPair("NAS100", "US100");
   AddAliasPair("NAS100", "USTECH");
   AddAliasPair("NAS100", "NQ");
   AddAliasPair("NAS100", "NQ100");
   AddAliasPair("NAS100", "USTECH100");

   // US INDICES -- Russell
   AddAliasPair("US2000", "RUSSELL");
   AddAliasPair("US2000", "RTY");
   AddAliasPair("US2000", "RUSSELL2000");
   AddAliasPair("US2000", "RUS2000");
   AddAliasPair("US2000", "RUT");

   // EUROPEAN INDICES -- DAX
   AddAliasPair("GER40", "DAX40");
   AddAliasPair("GER40", "DE40");
   AddAliasPair("GER40", "GER30");
   AddAliasPair("GER40", "DAX30");
   AddAliasPair("GER40", "DE30");
   AddAliasPair("GER40", "GDAXI");
   AddAliasPair("GER40", "DAX");

   // EUROPEAN INDICES -- FTSE
   AddAliasPair("UK100", "FTSE100");
   AddAliasPair("UK100", "FTSE");
   AddAliasPair("UK100", "UKX");

   // EUROPEAN INDICES -- CAC
   AddAliasPair("FRA40", "CAC40");
   AddAliasPair("FRA40", "FR40");
   AddAliasPair("FRA40", "F40");
   AddAliasPair("FRA40", "CAC");

   // EUROPEAN INDICES -- Euro Stoxx
   AddAliasPair("EUSTX50", "EU50");
   AddAliasPair("EUSTX50", "STOXX50");
   AddAliasPair("EUSTX50", "SX5E");
   AddAliasPair("EUSTX50", "EUROSTOXX50");

   // EUROPEAN INDICES -- Swiss
   AddAliasPair("SUI20", "SMI20");
   AddAliasPair("SUI20", "SMI");

   // EUROPEAN INDICES -- Spain
   AddAliasPair("ESP35", "SPA35");
   AddAliasPair("ESP35", "ES35");
   AddAliasPair("ESP35", "IBEX35");
   AddAliasPair("ESP35", "IBEX");

   // EUROPEAN INDICES -- Netherlands & Italy
   AddAliasPair("NETH25", "AEX25");
   AddAliasPair("NETH25", "AEX");
   AddAliasPair("ITA40",  "FTMIB");
   AddAliasPair("ITA40",  "IT40");

   // ASIA-PACIFIC INDICES -- Japan
   AddAliasPair("JPN225", "JP225");
   AddAliasPair("JPN225", "NIKKEI225");
   AddAliasPair("JPN225", "NIK225");
   AddAliasPair("JPN225", "NIKKEI");
   AddAliasPair("JPN225", "NK225");

   // ASIA-PACIFIC INDICES -- Australia
   AddAliasPair("AUS200", "ASX200");
   AddAliasPair("AUS200", "AU200");

   // ASIA-PACIFIC INDICES -- Hong Kong
   AddAliasPair("HK50", "HSI50");
   AddAliasPair("HK50", "HSI");
   AddAliasPair("HK50", "HANGSENG");

   // ASIA-PACIFIC INDICES -- China
   AddAliasPair("CHN50", "CHINA50");
   AddAliasPair("CHN50", "CHINAH");
   AddAliasPair("CHN50", "A50");
   AddAliasPair("CHN50", "FTCHINA");

   // ASIA-PACIFIC INDICES -- India / Singapore
   AddAliasPair("IND50", "NIFTY50");
   AddAliasPair("IND50", "NIFTY");
   AddAliasPair("SGD30", "STI");
   AddAliasPair("SGD30", "SG30");

   // DOLLAR INDEX
   AddAliasPair("USDX", "DXY");
   AddAliasPair("USDX", "DOLLARINDEX");
   AddAliasPair("USDX", "DX");
   AddAliasPair("USDX", "DOLLAR");

   // CRYPTO
   AddAliasPair("BTCUSD",   "BITCOIN");
   AddAliasPair("BTCUSD",   "BTC");
   AddAliasPair("BTCUSD",   "BTCUSDT");
   AddAliasPair("BTCUSD",   "XBT");
   AddAliasPair("BTCUSD",   "XBTUSD");
   AddAliasPair("ETHUSD",   "ETHEREUM");
   AddAliasPair("ETHUSD",   "ETH");
   AddAliasPair("ETHUSD",   "ETHUSDT");
   AddAliasPair("LTCUSD",   "LITECOIN");
   AddAliasPair("LTCUSD",   "LTC");
   AddAliasPair("XRPUSD",   "RIPPLE");
   AddAliasPair("XRPUSD",   "XRP");
   AddAliasPair("SOLUSD",   "SOLANA");
   AddAliasPair("SOLUSD",   "SOL");
   AddAliasPair("DOGEUSD",  "DOGE");
   AddAliasPair("ADAUSD",   "CARDANO");
   AddAliasPair("ADAUSD",   "ADA");
   AddAliasPair("DOTUSD",   "POLKADOT");
   AddAliasPair("DOTUSD",   "DOT");
   AddAliasPair("AVAXUSD",  "AVALANCHE");
   AddAliasPair("BNBUSD",   "BNB");
   AddAliasPair("MATICUSD", "MATIC");
   AddAliasPair("LINKUSD",  "CHAINLINK");
   AddAliasPair("LINKUSD",  "LINK");

   // BONDS
   AddAliasPair("BUND",    "EURBUND");
   AddAliasPair("TNOTE",   "USTNOTE");
   AddAliasPair("USTBOND", "USBOND");
   AddAliasPair("USTBOND", "ZB");

   // AGRICULTURAL
   AddAliasPair("COCOA",   "CC");
   AddAliasPair("COFFEE",  "KC");
   AddAliasPair("COTTON",  "CT");
   AddAliasPair("SUGAR",   "SB");
   AddAliasPair("WHEAT",   "ZW");
   AddAliasPair("CORN",    "ZC");
   AddAliasPair("SOYBEAN", "ZS");

   Print("[INIT] SymbolResolver v6.00: ", g_sfxCount, " suffixes, ", g_naliasCount, " alias pairs loaded");
}

//+------------------------------------------------------------------+
// WORD-BOUNDARY FIND: Matches whole words only (prevents BUYING matching BUY)
// Returns position of word if found as a whole word, -1 otherwise.
//+------------------------------------------------------------------+
int WordFind(string haystack, string needle)
{
   int pos = 0;
   int needleLen = StringLen(needle);
   int haystackLen = StringLen(haystack);
   
   // [v6.00 FIX 2026-04-26][R9] Empty-needle guard. Without this, an empty needle would
   // make StringFind return pos every iteration and the loop would never advance because
   // needleLen == 0. Defensive even though current callers should never pass empty strings.
   if(needleLen == 0) return -1;
   
   while(true)
   {
      int found = StringFind(haystack, needle, pos);
      if(found < 0) return -1;
      
      // Check left boundary: start of string or non-alpha char before
      bool leftOK = (found == 0);
      if(!leftOK)
      {
         ushort c = StringGetCharacter(haystack, found - 1);
         leftOK = !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'));
      }
      
      // Check right boundary: end of string or non-alpha char after
      int afterPos = found + needleLen;
      bool rightOK = (afterPos >= haystackLen);
      if(!rightOK)
      {
         ushort c = StringGetCharacter(haystack, afterPos);
         rightOK = !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'));
      }
      
      if(leftOK && rightOK) return found;
      pos = found + 1;
   }
   return -1;
}

//+------------------------------------------------------------------+
// [v6.01 FIX] Daily-loss helpers — prop-firm-correct boundary + anchor.
//+------------------------------------------------------------------+

// Returns the most recent day-rollover instant (00:00 in the configured TZ),
// expressed in the same numeric domain as `TimeCurrent()` (i.e. broker time
// epoch). Callers compare against this to bucket deals by trading day.
//
// Why: TimeCurrent() is broker-server time, typically GMT+2/+3. Most prop
// firms reset daily P/L at UTC midnight, NOT at broker midnight. Using the
// wrong boundary lets a trader cross the prop firm's day-end while the EA
// still thinks it's the same day -- the daily loss limit doesn't reset, OR
// resets too early, depending on direction. Either way: blown account.
datetime TCU_GetDailyAnchorTime()
{
   datetime brokerNow = TimeCurrent();
   datetime utcNow    = TimeGMT();

   // Broker server's offset from UTC (positive = east of UTC).
   long brokerOffsetSec = (long)brokerNow - (long)utcNow;

   if(DailyResetTimezone == DAILY_TZ_UTC)
   {
      // Compute UTC midnight, then translate back into broker-time domain.
      MqlDateTime u;
      TimeToStruct(utcNow, u);
      datetime utcMidnight = StringToTime(
         IntegerToString(u.year) + "." +
         IntegerToString(u.mon)  + "." +
         IntegerToString(u.day));
      return utcMidnight + (datetime)brokerOffsetSec;
   }

   // DAILY_TZ_BROKER (legacy default): broker-time midnight.
   MqlDateTime b;
   TimeToStruct(brokerNow, b);
   return StringToTime(
      IntegerToString(b.year) + "." +
      IntegerToString(b.mon)  + "." +
      IntegerToString(b.day));
}

// Captures start-of-day balance + initial peak equity once per day-rollover.
// Cheap to call repeatedly: only does work when the anchor date changes.
// Also continuously ratchets g_dailyPeakEquity upward so the trailing-
// drawdown check (DailyLossUsePeakEquity) has a fresh reference.
void TCU_RolloverDailyAnchorIfNeeded()
{
   datetime anchorNow = TCU_GetDailyAnchorTime();

   if(anchorNow != g_dailyAnchorDate)
   {
      g_dailyAnchorDate   = anchorNow;
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyPeakEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("[SAFETY] Daily anchor rolled over. StartBalance=$",
            DoubleToString(g_dailyStartBalance, 2),
            " PeakEquity=$", DoubleToString(g_dailyPeakEquity, 2),
            " Boundary=", (DailyResetTimezone == DAILY_TZ_UTC ? "UTC" : "BROKER"));
   }

   // Ratchet peak equity. Cheap, runs every cache-miss tick.
   double currentEq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEq > g_dailyPeakEquity) g_dailyPeakEquity = currentEq;
}

//+------------------------------------------------------------------+
// DAILY LOSS LIMIT: Check if today's losses exceed the allowed threshold
// Uses deal history (realized P/L) + open position P/L (unrealized)
//
// [v6.01 FIX] Two anchor modes, both checked when configured:
//   1. STATIC: lossPct = totalPL / startOfDayBalance
//      Catches "lost X% of where I started today" — most prop firms.
//   2. PEAK (DailyLossUsePeakEquity=true, default): drawdownPct =
//      (peakEquity - currentEquity) / peakEquity
//      Catches "made profit then gave it all back" — FTMO and similar.
// Whichever fires first wins. This is strictly safer than the legacy
// "anchor to current balance" logic which silently masked Mode 2.
//+------------------------------------------------------------------+
bool IsDailyLossLimitHit()
{
   // Cache result briefly to avoid heavy history queries on every signal
   static datetime lastCheck = 0;
   static bool lastResult = false;
   datetime now = TimeCurrent();
   if(g_dailyLossCacheInvalidAfter != 0)
   {
      lastCheck = 0;
      g_dailyLossCacheInvalidAfter = 0;
   }

   // [v6.01 FIX] Rollover + peak ratchet must happen on EVERY call,
   // even cache hits, so peak equity tracking stays current.
   TCU_RolloverDailyAnchorIfNeeded();

   if(now - lastCheck < 10) return lastResult;
   lastCheck = now;

   // [v6.01 FIX] Use the configured-TZ day-start, not broker midnight.
   datetime todayStart = g_dailyAnchorDate;

   // Calculate realized P/L from today's closed deals
   double realizedPL = 0;
   if(HistorySelect(todayStart, now))
   {
      int totalDeals = HistoryDealsTotal();
      for(int i = 0; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
         {
            // [v6.02 FIX] Only count closing deals -- skip DEAL_ENTRY_IN, balance ops, etc.
            long dEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(dEntry != DEAL_ENTRY_OUT && dEntry != DEAL_ENTRY_INOUT) continue;
            long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            if(dealMagic == MagicNumber || MagicNumber == 0)
            {
               realizedPL += HistoryDealGetDouble(ticket, DEAL_PROFIT);
               realizedPL += HistoryDealGetDouble(ticket, DEAL_SWAP);
               realizedPL += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            }
         }
      }
   }

   // Calculate unrealized P/L from open positions
   double unrealizedPL = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber || MagicNumber == 0)
         {
            unrealizedPL += PositionGetDouble(POSITION_PROFIT);
            unrealizedPL += PositionGetDouble(POSITION_SWAP);
         }
      }
   }

   double totalPL    = realizedPL + unrealizedPL;
   double currentEq  = AccountInfoDouble(ACCOUNT_EQUITY);

   // [v6.01 FIX] Anchor to start-of-day balance, NOT current balance.
   // Fall back to current balance only if anchor wasn't captured yet
   // (first tick after EA load, before TCU_RolloverDailyAnchorIfNeeded
   // ran). Defensive: never zero-divide.
   double anchorBalance = (g_dailyStartBalance > 0) ? g_dailyStartBalance
                                                    : AccountInfoDouble(ACCOUNT_BALANCE);

   double effectiveMaxLossPct = TCU_EffectiveMaxDailyLossPercent();

   // ── Check 1: STATIC daily loss vs start-of-day balance ─────────────
   if(effectiveMaxLossPct > 0 && anchorBalance > 0)
   {
      double lossPercent = (totalPL / anchorBalance) * 100.0;
      if(lossPercent <= -effectiveMaxLossPct)
      {
         Print("[SAFETY] Daily loss limit HIT (static): ",
               DoubleToString(lossPercent, 2), "% of start-of-day balance $",
               DoubleToString(anchorBalance, 2),
               " | limit -", DoubleToString(effectiveMaxLossPct, 2),
               "% | P/L $", DoubleToString(totalPL, 2));
         lastResult = true;
         return true;
      }
   }

   // ── Check 2: PEAK-equity drawdown (catches "gave back profits") ───
   if(DailyLossUsePeakEquity && effectiveMaxLossPct > 0
      && g_dailyPeakEquity > 0 && currentEq > 0)
   {
      double drawdown    = g_dailyPeakEquity - currentEq;
      double drawdownPct = (drawdown / g_dailyPeakEquity) * 100.0;
      if(drawdownPct >= effectiveMaxLossPct)
      {
         Print("[SAFETY] Daily loss limit HIT (peak DD): ",
               DoubleToString(drawdownPct, 2),
               "% from peak $", DoubleToString(g_dailyPeakEquity, 2),
               " -> current $", DoubleToString(currentEq, 2),
               " | limit ", DoubleToString(effectiveMaxLossPct, 2), "%");
         lastResult = true;
         return true;
      }
   }

   // ── Check 3: dollar-amount limit (vs start-of-day balance) ────────
   if(MaxDailyLossAmount > 0)
   {
      if(totalPL <= -MaxDailyLossAmount)
      {
         Print("[SAFETY] Daily loss limit HIT ($): $",
               DoubleToString(MathAbs(totalPL), 2),
               " (limit: $", DoubleToString(MaxDailyLossAmount, 2), ")");
         lastResult = true;
         return true;
      }
   }

   lastResult = false;
   return false;
}

//+------------------------------------------------------------------+
// MESSAGE SKIP FILTER: Two-tier skip system
//   HARD-SKIP: Always skip (status/results/commentary -- never an entry)
//   SOFT-SKIP: Skip ONLY if message lacks real signal markers (dir+sym+SL/TP)
// Prevents status messages from trading, but allows "VIP SIGNAL BUY XAUUSD" through
//+------------------------------------------------------------------+
bool ContainsSkipKeyword(string uMsg)
{
   // ===== HARD-SKIP: Signal status/result messages (NEVER a new entry) =====
   // NOTE: Use space-padded strings to avoid substring false-matches
   // e.g. "CLOSED" must NOT match "CLOSE ALL" or "CLOSE GOLD"
   // Prepend/append spaces to uMsg for boundary checks
   string uMsgPad = " " + uMsg + " ";
   if(StringFind(uMsgPad, " HIT TP") >= 0  || StringFind(uMsgPad, " HIT SL") >= 0  ||
      StringFind(uMsgPad, " TP HIT") >= 0  || StringFind(uMsgPad, " SL HIT") >= 0  ||
      StringFind(uMsgPad, "TP REACHED") >= 0 || StringFind(uMsgPad, "SL REACHED") >= 0 ||
      StringFind(uMsgPad, " RUNNING ") >= 0 ||
      StringFind(uMsgPad, " CLOSED ") >= 0 || StringFind(uMsgPad, " CLOSED\n") >= 0 || StringFind(uMsgPad, "CLOSED!") >= 0 ||
      StringFind(uMsg, "IN PROFIT") >= 0   || StringFind(uMsg, "IN LOSS") >= 0 ||
      StringFind(uMsg, "PIPS PROFIT") >= 0 || StringFind(uMsg, "PIPS LOSS") >= 0 ||
      StringFind(uMsg, "RESULT") >= 0      || StringFind(uMsg, "RECAP") >= 0 ||
      StringFind(uMsg, "OUTCOME") >= 0     ||
      StringFind(uMsg, "SECURED") >= 0     || StringFind(uMsg, "BANKED") >= 0 ||
      StringFind(uMsg, "BOOKED") >= 0      || StringFind(uMsg, "STOPPED OUT") >= 0)
      return true;
   
   // ===== HARD-SKIP: Commentary / past-tense / opinion (NEVER a new entry) =====
   if(WordFind(uMsg, "WAS") >= 0 || WordFind(uMsg, "WERE") >= 0 ||
      WordFind(uMsg, "YESTERDAY") >= 0 || StringFind(uMsg, "LAST WEEK") >= 0 ||
      WordFind(uMsg, "FAILED") >= 0 || WordFind(uMsg, "ALREADY") >= 0 ||
      WordFind(uMsg, "PREVIOUS") >= 0 || WordFind(uMsg, "DIDN") >= 0 ||
      StringFind(uMsg, "DID NOT") >= 0 || StringFind(uMsg, "SHOULD HAVE") >= 0 ||
      StringFind(uMsg, "COULD HAVE") >= 0 || StringFind(uMsg, "WOULD HAVE") >= 0 ||
      WordFind(uMsg, "MIGHT") >= 0 || WordFind(uMsg, "MAYBE") >= 0 ||
      WordFind(uMsg, "DONT") >= 0 || StringFind(uMsg, "DON'T") >= 0 ||
      StringFind(uMsg, "NOT A ") >= 0 || StringFind(uMsg, "NO TRADE") >= 0 ||
      StringFind(uMsg, "NO SIGNAL") >= 0 || StringFind(uMsg, "NO ENTRY") >= 0 ||
      StringFind(uMsg, "PREDICTION") >= 0 || StringFind(uMsg, "FORECAST") >= 0 ||
      StringFind(uMsg, "MY BRO") >= 0 || WordFind(uMsg, "SOMEONE") >= 0 ||
      WordFind(uMsg, "OPINION") >= 0 || StringFind(uMsg, "I THINK") >= 0 ||
      StringFind(uMsg, "LOOKING AT") >= 0)
      return true;
   
   // ===== SOFT-SKIP: Promo/noise -- skip ONLY if NOT a real signal =====
   // "VIP SIGNAL BUY XAUUSD SL 2600 TP 2650" => has direction+SL+TP => let it through!
   // "Join our VIP channel for free signals" => no direction => skip it
   bool hasSoftSkip = false;
   if(WordFind(uMsg, "JOIN") >= 0 || StringFind(uMsg, "SUBSCRIBE") >= 0 ||
      StringFind(uMsg, "FREE SIGNAL") >= 0 || StringFind(uMsg, "PREMIUM") >= 0 ||
      WordFind(uMsg, "VIP") >= 0 || StringFind(uMsg, "DISCOUNT") >= 0 ||
      StringFind(uMsg, "CONGRATULATIONS") >= 0 || StringFind(uMsg, "WELL DONE") >= 0 ||
      StringFind(uMsg, "GREAT TRADE") >= 0 || StringFind(uMsg, "HOW TO") >= 0 ||
      StringFind(uMsg, "TUTORIAL") >= 0 || StringFind(uMsg, "LESSON") >= 0 ||
      WordFind(uMsg, "WEEKLY") >= 0 || WordFind(uMsg, "MONTHLY") >= 0 ||
      StringFind(uMsg, "DAILY REPORT") >= 0 || WordFind(uMsg, "SUMMARY") >= 0 ||
      WordFind(uMsg, "FOLLOW") >= 0 || StringFind(uMsg, "LIKE AND") >= 0 ||
      WordFind(uMsg, "SHARE") >= 0 || WordFind(uMsg, "REVIEW") >= 0 ||
      WordFind(uMsg, "ANALYSIS") >= 0 || StringFind(uMsg, "WATCHING") >= 0 ||
      StringFind(uMsg, "SIGNAL UPDATE") >= 0 || StringFind(uMsg, "TRADE UPDATE") >= 0 ||
      StringFind(uMsg, "ACTIVE TRADE") >= 0 || StringFind(uMsg, "STATUS UPDATE") >= 0 ||
      StringFind(uMsg, "STILL ACTIVE") >= 0)
      hasSoftSkip = true;
   
   if(hasSoftSkip)
   {
      // Check if message ALSO has real signal markers (direction + SL or TP or entry price)
      bool hasDirection = (WordFind(uMsg, "BUY") >= 0 || WordFind(uMsg, "SELL") >= 0 ||
                           WordFind(uMsg, "LONG") >= 0 || WordFind(uMsg, "SHORT") >= 0);
      bool hasPrice = (StringFind(uMsg, "SL") >= 0 || StringFind(uMsg, "TP") >= 0 ||
                       StringFind(uMsg, "ENTRY") >= 0 || StringFind(uMsg, "STOPLOSS") >= 0 ||
                       StringFind(uMsg, "STOP LOSS") >= 0 || StringFind(uMsg, "TAKE PROFIT") >= 0 ||
                       StringFind(uMsg, "@") >= 0);
      
      if(hasDirection && hasPrice)
      {
         Print("[FILTER] Soft-skip word found but message has signal markers -- allowing through");
         return false;  // Let it through -- it looks like a real signal
      }
      return true;  // No signal markers -- just promo noise
   }
   
   // ===== USER-DEFINED: Custom skip keywords from input parameter =====
   if(EnableSkipKeywords && StringLen(SkipKeywords) > 0)
   {
      string kws[];
      string kwList = SkipKeywords;
      StringReplace(kwList, ", ", ",");
      int cnt = StringSplit(kwList, ',', kws);
      for(int i = 0; i < cnt; i++)
      {
         string kw = kws[i];
         StringTrimLeft(kw);
         StringTrimRight(kw);
         StringToUpper(kw);
         if(StringLen(kw) > 0 && StringFind(uMsg, kw) >= 0)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void SendBridgeHeartbeat()
{
   if(!EnableBridgeMode) return;
   if(g_bridgeFailCount > 0) return;   // Bridge unreachable — skip to avoid blocking UI
   string broker  = AccountInfoString(ACCOUNT_COMPANY);
   string account = StringFormat("%I64d", (long)AccountInfoInteger(ACCOUNT_LOGIN));

   // Build broker_symbols JSON array from Market Watch
   string symsJson = "[";
   int symTotal = SymbolsTotal(true);
   for(int si = 0; si < symTotal && si < 200; si++)
   {
      if(si > 0) symsJson += ",";
      symsJson += "\"" + SymbolName(si, true) + "\"";
   }
   symsJson += "]";

   // Build pending_tickets JSON array from heartbeat buffer
   string ticketsJson = "[";
   for(int ti = 0; ti < g_hbBufCount; ti++)
   {
      if(ti > 0) ticketsJson += ",";
      ticketsJson += "{\"signal_ref\":\"" + g_hbRefBuf[ti]
                  + "\",\"ticket\":"      + IntegerToString((long)g_hbTicketBuf[ti])
                  + ",\"symbol\":\""      + g_hbSymBuf[ti] + "\"}";
   }
   ticketsJson += "]";

   // Account equity & balance
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   string eqStr  = DoubleToString(eq,  2);
   string balStr = DoubleToString(bal, 2);

   // Martingale per-symbol state (only when MG is active)
   string mgJson = "[]";
   if(EnableMartingale && g_mgCount > 0)
   {
      mgJson = "[";
      bool _mgFirst = true;
      for(int mi = 0; mi < g_mgCount; mi++)
      {
         if(g_mgTable[mi].streak == 0 && g_mgTable[mi].mgPnl == 0) continue;
         if(!_mgFirst) mgJson += ",";
         _mgFirst = false;
         mgJson += "{\"sym\":\""    + g_mgTable[mi].sym
                 + "\",\"streak\":" + IntegerToString(g_mgTable[mi].streak)
                 + ",\"pnl\":"      + DoubleToString(g_mgTable[mi].mgPnl, 2)
                 + ",\"wins\":"     + IntegerToString(g_mgTable[mi].wins)
                 + ",\"losses\":"   + IntegerToString(g_mgTable[mi].losses)
                 + ",\"last_pnl\":" + DoubleToString(g_mgTable[mi].lastPnl, 2)
                 + "}";
      }
      mgJson += "]";
   }

   string body = "{\"broker\":\""        + JsonEscape(broker) + "\""
               + ",\"account\":\""       + account            + "\""
               + ",\"equity\":"          + eqStr
               + ",\"balance\":"         + balStr
               + ",\"broker_symbols\":"  + symsJson
               + ",\"pending_tickets\":" + ticketsJson
               + ",\"mg_enabled\":"      + (EnableMartingale ? "true" : "false")
               + ",\"mg_mode\":"         + IntegerToString(MartingaleMode)
               + ",\"mg_state\":"        + mgJson
               + "}";

   uchar post[], result[];
   StringToCharArray(body, post, 0, StringLen(body), CP_UTF8);
   string headers = "Content-Type: application/json\r\n"
                  + "X-NTS-Auth: "  + NTS_AuthToken() + "\r\n"
                  + "X-Client-Id: " + NTS_ClientId()  + "\r\n";
   string respHeaders;
   int res = WebRequest("POST",
                        "http://127.0.0.1:" + IntegerToString(BridgePort) + "/heartbeat",
                        headers, 1500, post, result, respHeaders);
   if(res == 200)
   {
      if(g_hbBufCount > 0)
         Print("[Bridge] Heartbeat OK -- ", g_hbBufCount, " pending ticket(s) registered via backup path");
      else
         Print("[Bridge] Heartbeat OK. broker=", broker, " acct=", account, " symbols=", symTotal);
      g_hbBufCount = 0;
      ArrayResize(g_hbRefBuf,    0);
      ArrayResize(g_hbTicketBuf, 0);
      ArrayResize(g_hbSymBuf,    0);
   }
   else if(res == -1)
      Print("[Bridge] Heartbeat blocked -- add http://127.0.0.1 to MT5 WebRequest URLs");
   else
      Print("[Bridge] Heartbeat HTTP=", res);
}

//+------------------------------------------------------------------+
void PollBridge()
{
   ulong now = GetTickCount64();
   if(g_bridgeFailCount >= 1 && now < g_bridgeNextRetry) return;
   
   string headers = "X-NTS-Auth: " + NTS_AuthToken() + "\r\n"
                  + "X-Client-Id: " + NTS_ClientId() + "\r\n";
   char   post[], result[];
   string respHdr;
   string url = "http://127.0.0.1:" + IntegerToString(BridgePort) + "/signals/copier";
   ResetLastError();
   int res = WebRequest("GET", url, headers, 1500, post, result, respHdr);
   
   if(res != 200)
   {
      g_bridgeFailCount++;
      // First failure: retry in 2s (handles broker rate-limiting / transient timeouts).
      // Only enter long 30s backoff after 2+ consecutive failures (bridge truly offline).
      g_bridgeNextRetry = now + (g_bridgeFailCount >= 2 ? 30000 : 2000);
      if(res == -1 && g_bridgeFailCount <= 2) Print("[Bridge] Connection blocked! Add 'http://127.0.0.1' to MT5 > Tools > Options > Expert Advisors > Allow WebRequest URLs.");
      else if(g_bridgeFailCount <= 2) Print("[Bridge] Offline (HTTP ", res, "). Retry ", (g_bridgeFailCount >= 2 ? "30" : "2"), "s");
      return;
   }
   
   if(g_bridgeFailCount > 0)
   {
      Print("[Bridge] Connected! Resuming live polling.");
      g_bridgeFailCount = 0;
   }
   
   string resp = CharArrayToString(result);
   // [v6.00 FIX 2026-04-26][R5] Privacy: only dump raw bridge response when DiagLog is on.
   // Previously every successful poll printed up to 300 chars of the response, which contains
   // raw signal text from private channels. With DiagLog OFF (the default for paying users), we
   // log only metadata. With DiagLog ON, the trader has explicitly asked for full traces.
   if(StringLen(resp) > 20)
   {
      if(EnableDiagLog)
         Print("[Bridge] Response (", StringLen(resp), " chars): ", StringSubstr(resp, 0, 300));
      else
         Print("[Bridge] Response received (", StringLen(resp), " chars). Enable DiagLog for content trace.");
   }
   ParseBridgeResp(resp);
}



//+------------------------------------------------------------------+
string NTS_AuthToken()
{
   return "NTS-2026-XQFZ8K4M-NAVIGATOR-AUTH";
}

//+------------------------------------------------------------------+
void ParseBridgeResp(string json)
{
   int sStart = StringFind(json, "\"signals\"");
   if(sStart < 0) return;
   int aStart = StringFind(json, "[", sStart);
   if(aStart < 0) return;
   int n = StringLen(json);

   // Empty array? (first non-space char after '[' is ']')
   int probe = aStart + 1;
   while(probe < n)
   {
      ushort pc = StringGetCharacter(json, probe);
      if(pc != ' ' && pc != '\t' && pc != '\r' && pc != '\n') break;
      probe++;
   }
   if(probe >= n || StringGetCharacter(json, probe) == ']') return;

   // Startup drain: skip signals for 10 seconds after EA init to avoid stale signals.
   // This avoids the old "single poll drain" that left the 2nd poll at risk.
   if(g_bridgeFirstPoll)
   {
      ulong sinceStart = GetTickCount64() - g_startupTickCount;
      if(sinceStart < 10000)
      {
         Print("[Bridge] Startup drain active (", (int)(sinceStart/1000), "s / 10s) -- NOT executing signals yet.");
         ClearBridgeSigs(true);   // broad drain: wipe all stale signals
         return;
      }
      g_bridgeFirstPoll = false;
      Print("[Bridge] Startup drain complete -- now accepting signals.");
   }

   // String-aware scan: capture each top-level {...} object inside the signals
   // array. Quotes and escapes are respected, so braces/brackets inside a
   // signal's raw text can never corrupt the object boundaries.
   ArrayResize(g_bridgeAckIds, 0);   // fresh ACK accumulator for this poll
   int depth = 0, objStart = -1, sigCount = 0;
   bool inStr = false;
   for(int i = aStart + 1; i < n && sigCount < 100; i++)
   {
      ushort c = StringGetCharacter(json, i);
      if(inStr)
      {
         if(c == 92) { i++; continue; }   // skip escaped char
         if(c == 34) inStr = false;
         continue;
      }
      if(c == 34) { inStr = true; continue; }
      if(c == 93 && depth == 0) break;     // ']' closes the signals array
      if(c == 123)                         // '{'
      {
         if(depth == 0) objStart = i;
         depth++;
      }
      else if(c == 125)                    // '}'
      {
         if(depth > 0) depth--;
         if(depth == 0 && objStart >= 0)
         {
            ProcessBridgeSig(StringSubstr(json, objStart, i - objStart + 1));
            sigCount++;
            objStart = -1;
         }
      }
   }
   if(sigCount > 0) { Print("[Bridge] Processed ", sigCount, " signal(s)"); ClearBridgeSigs(); }
}

//+------------------------------------------------------------------+
void ProcessBridgeSig(string obj)
{
   // [v6.x FIX] Capture this signal's queue id for the targeted /signals/clear
   // ACK. Done before any early-return so every signal we actually received
   // is acked (executed, skipped or filtered alike). Signals that arrive AFTER
   // our GET are never passed here, stay unacked, and get re-served next poll
   // instead of being silently dropped by a broad clear.
   int _ackId = (int)ExtractJsonDbl(obj, "id");
   if(_ackId > 0)
   {
      int _an = ArraySize(g_bridgeAckIds);
      ArrayResize(g_bridgeAckIds, _an + 1);
      g_bridgeAckIds[_an] = _ackId;
   }

   // [v6.00 FIX 2026-04-26][R5] Privacy: gate raw JSON dump behind DiagLog (private channel content).
   if(EnableDiagLog) Print("[Bridge] RAW JSON: ", StringSubstr(obj, 0, 250));
   
   string raw      = ExtractJsonStr(obj, "raw");
   string srcId    = ExtractJsonFlexStr(obj, "chat_id");
   if(srcId == "") srcId = ExtractJsonFlexStr(obj, "source_id");
   if(srcId == "") srcId = ExtractJsonFlexStr(obj, "channel_id");
    string srcName  = ExtractJsonStr(obj, "source_name");
   if(srcName == "") srcName = ExtractJsonStr(obj, "chat_title");
   if(srcName == "") srcName = ExtractJsonStr(obj, "channel");

   // Store signal_ref for ticket callback after successful trade execution
   g_currentSignalRef = ExtractJsonStr(obj, "signal_ref");
   // Note: intentionally no fallback to "Bridge" — if bridge sends blank source_name
   // (prop firm mode), the MT5 trade comment stays empty as required.
    
   // Collapse newlines/tabs to spaces so the text matches the ProcessTextSig format.
   // (ExtractJsonStr now decodes JSON escapes, so these are real control chars.)
   StringReplace(raw, "\n", " ");
   StringReplace(raw, "\r", " ");
   StringReplace(raw, "\t", " ");
   
   string rawUp = raw; StringToUpper(rawUp);
   
   // ROUTE 1: If raw text exists, route it directly to the EA's internal text parser (ProcessTextSig)
   // This guarantees 100% identical parsing for Telegram API mode and Bridge mode!
   // ProcessTextSig handles: trade signals, close all, breakeven, move sl, and ignores unknown text.
   if(StringLen(raw) > 3)
   {
      // [v6.00 FIX 2026-04-26][R5] Privacy: gate signal text preview behind DiagLog.
      if(EnableDiagLog) Print("[Bridge] Routing raw text to ProcessTextSig: ", StringSubstr(raw, 0, 80));
      ProcessTextSig(raw, srcName);
      return;
   }
   
   // ROUTE 2: Fallback to JSON fields if raw text doesn't exist or isn't a trade signal 
   string dir      = ExtractJsonStr(obj, "direction");
   string sym      = ExtractJsonStr(obj, "symbol");
   double sl       = ExtractJsonDbl(obj, "sl");
   double tp       = ExtractJsonDbl(obj, "tp");
   double tp2      = ExtractJsonDbl(obj, "tp2");
   double tp3      = ExtractJsonDbl(obj, "tp3");
   double lot      = ExtractJsonDbl(obj, "lot");
   if(!EnableSignalTP)
   {
      tp = 0; tp2 = 0; tp3 = 0;
   }
   string ts       = ExtractJsonStr(obj, "timestamp");
   
   StringToUpper(dir);
   Print("[Bridge] PARSED: ", dir, " ", sym, " SL=", sl, " TP=", tp, " FROM=[", srcName, "]");
   
   // ANTI-LOOP: Skip signals that originated from this EA
   // Check 1: user-configured send tag
   string tagUp = TelegramSendTag; StringToUpper(tagUp);
   if(StringLen(tagUp) > 0 && StringFind(rawUp, tagUp) >= 0)
   { Print("[Bridge] Skipping own broadcast (anti-loop, tag match)"); return; }
   // Check 2: fixed permanent anti-loop marker (hardcoded, survives any tag/magic change)
   if(StringFind(rawUp, "NTS-BCT") >= 0)
   { Print("[Bridge] Skipping own broadcast (anti-loop, permanent marker)"); return; }
   // Check 3: structural pattern -- " ENTRY: " + " LOTS: " is exclusively our broadcast format
   if(StringFind(rawUp, " ENTRY: ") >= 0 && StringFind(rawUp, " LOTS: ") >= 0)
   { Print("[Bridge] Skipping own broadcast (anti-loop, entry/lots pattern)"); return; }
   
   // SKIP KEYWORD FILTER
   if(ContainsSkipKeyword(rawUp))
   { Print("[Bridge] Skipped status: ", StringSubstr(raw, 0, 60)); return; }
   
   // PENDING ORDER: If Bridge JSON sends a structured pending signal (dir = BUY/SELL, signal_type = buy_limit etc.)
   // Route it to PlacePending order via OrderOpen instead of skipping
   string sigType = ExtractJsonStr(obj, "signal_type");
   StringToLower(sigType);
   if(StringFind(sigType, "limit") >= 0 || StringFind(sigType, "stop") >= 0)
   {
      if(!EnablePendingOrders)
      { Print("[Bridge] Pending signal ignored: EnablePendingOrders=false. Type=", sigType); return; }
      if(!ArmExecution)
      {
         g_lastFilterReason = "DISARMED";
         Print("[Bridge] Pending rejected -- EA is DISARMED: ", sigType);
         return;
      }
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      {
         string why = !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
                      ? "AutoTrading is OFF in MT5 toolbar -- click the AutoTrading button"
                      : "AlgoTrading disabled for this EA -- enable in EA properties (Common tab)";
         g_lastFilterReason = why;
         Print("[Bridge] Pending rejected -- ", why);
         return;
      }
      double pEntry = ExtractJsonDbl(obj, "entry_price");
      if(pEntry <= 0) pEntry = ExtractJsonDbl(obj, "entry");
      if(pEntry <= 0) { Print("[Bridge] Pending: no entry price in JSON, skipping"); return; }
      ENUM_ORDER_TYPE otype;
      if(sigType == "buy_limit")        otype = ORDER_TYPE_BUY_LIMIT;
      else if(sigType == "sell_limit")  otype = ORDER_TYPE_SELL_LIMIT;
      else if(sigType == "buy_stop")    otype = ORDER_TYPE_BUY_STOP;
      else if(sigType == "sell_stop")   otype = ORDER_TYPE_SELL_STOP;
      else { Print("[Bridge] Unknown pending type: ", sigType); return; }
      if(StringLen(sym) == 0) { Print("[Bridge] Pending: no symbol"); return; }
      sym = MapSym(sym);
      string bridgeDir = (StringFind(sigType, "buy") >= 0) ? "BUY" : "SELL";
      if(ReverseSignal)
      {
         if(bridgeDir == "BUY")
         {
            bridgeDir = "SELL";
            if(otype == ORDER_TYPE_BUY_LIMIT) otype = ORDER_TYPE_SELL_LIMIT;
            else if(otype == ORDER_TYPE_BUY_STOP) otype = ORDER_TYPE_SELL_STOP;
            StringReplace(sigType, "buy", "sell");
         }
         else
         {
            bridgeDir = "BUY";
            if(otype == ORDER_TYPE_SELL_LIMIT) otype = ORDER_TYPE_BUY_LIMIT;
            else if(otype == ORDER_TYPE_SELL_STOP) otype = ORDER_TYPE_BUY_STOP;
            StringReplace(sigType, "sell", "buy");
         }
         Print("[Bridge] ReverseSignal applied to pending -- using ", sigType);
      }
      if(IsNewsPauseActive(sym, true))
      {
         g_lastFilterReason = "News pause: " + g_tcuNewsLockReason;
         Print("[Bridge] Pending skipped by news pause: ", g_tcuNewsLockReason);
         return;
      }
      if(!IsSymbolAllowed(sym))
      {
         g_lastFilterReason = "Symbol filter";
         Print("[Bridge] Pending symbol ", sym, " blocked by whitelist/blacklist. Skipping.");
         return;
      }
      if(IsDailyLossLimitHit())
      {
         g_lastFilterReason = "Daily loss limit hit (bridge pending)";
         Print("[Bridge] Pending rejected -- daily loss limit hit: ", sigType, " ", sym);
         return;
      }
      int effectiveBridgePendMaxOpen = TCU_EffectiveMaxOpenPositions();
      if(effectiveBridgePendMaxOpen > 0 && (PositionsTotal() + OrdersTotal()) >= effectiveBridgePendMaxOpen)
      {
         g_lastFilterReason = "Max open positions reached (bridge pending)";
         Print("[Bridge] Pending rejected -- positions+pendings (", PositionsTotal(), "+", OrdersTotal(),
               ") >= cap (", effectiveBridgePendMaxOpen, ")");
         return;
      }
      double lots = CalcLots(sym, sl, lot, bridgeDir);
      if(SkipIfLotOverMax && lots > MaxLotSize)
      {
         Print("[Bridge] Pending lot too large - skipping: ", DoubleToString(lots, 2), " > ", DoubleToString(MaxLotSize, 2));
         g_lastFilterReason = "Lot > max";
         return;
      }
      int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      pEntry = NormalizeDouble(pEntry, dg);
      if(sl > 0) sl = NormalizeDouble(sl, dg);
      if(tp > 0) tp = NormalizeDouble(tp, dg);
      if(tp2 > 0) tp2 = NormalizeDouble(tp2, dg);
      if(tp3 > 0) tp3 = NormalizeDouble(tp3, dg);
      bool bridgeIsBuy = (bridgeDir == "BUY");
      double pipSizeB = PipSize(sym);
      if(EnableAutoSL && sl <= 0 && FallbackSLPips > 0)
      {
         sl = bridgeIsBuy ? (pEntry - FallbackSLPips * pipSizeB) : (pEntry + FallbackSLPips * pipSizeB);
         sl = NormalizeDouble(sl, dg);
         Print("[Bridge] Pending using Auto SL: ", DoubleToString(sl, dg));
      }
      if(EnableAutoTP && tp <= 0 && FallbackTPPips > 0)
      {
         tp = bridgeIsBuy ? (pEntry + FallbackTPPips * pipSizeB) : (pEntry - FallbackTPPips * pipSizeB);
         tp = NormalizeDouble(tp, dg);
         Print("[Bridge] Pending using Auto TP: ", DoubleToString(tp, dg));
      }
      if(SkipSignalWithoutSL && sl <= 0)
      {
         g_lastFilterReason = "No SL (bridge pending)";
         Print("[Bridge] Pending rejected -- no SL");
         return;
      }
      if(SkipSignalWithoutTP && tp <= 0)
      {
         g_lastFilterReason = "No TP (bridge pending)";
         Print("[Bridge] Pending rejected -- no TP");
         return;
      }
      if(PropFirmMode && sl <= 0)
      {
         g_lastFilterReason = "PropFirm: SL required";
         Print("[Bridge] Pending rejected -- PropFirmMode requires SL: ", sigType, " ", sym);
         return;
      }
      if(EnableTimeFilter)
      {
         MqlDateTime dtB; TimeCurrent(dtB);
         int curHourB = dtB.hour;
         bool inWindowB = false;
         if(TimeFilterStartHour <= TimeFilterEndHour)
            inWindowB = (curHourB >= TimeFilterStartHour && curHourB <= TimeFilterEndHour);
         else
            inWindowB = (curHourB >= TimeFilterStartHour || curHourB <= TimeFilterEndHour);
         if(!inWindowB)
         {
            g_lastFilterReason = "Outside time filter";
            Print("[Bridge] Pending time filter: hour=", curHourB, " outside ", TimeFilterStartHour, "-", TimeFilterEndHour);
            return;
         }
      }
      int bridgeSpread = (int)SymbolInfoInteger(sym, SYMBOL_SPREAD);
      int effectiveBridgeMaxSpread = TCU_EffectiveMaxSpreadPoints();
      if(TCU_EffectiveSpreadFilterEnabled() && bridgeSpread > effectiveBridgeMaxSpread)
      {
         g_lastFilterReason = "Spread: " + IntegerToString(bridgeSpread);
         Print("[Bridge] Pending spread too high! ", bridgeSpread, " > ", effectiveBridgeMaxSpread);
         return;
      }
      string bridgePendingHashKey = sigType + "|" + sym + "|" + DoubleToString(pEntry, dg) + "|" +
                                    DoubleToString(sl, dg) + "|" + DoubleToString(tp, dg) + "|" +
                                    DoubleToString(tp2, dg) + "|" + DoubleToString(tp3, dg) + "|" + ts;
      ulong bridgePendingHash = CalcHash(bridgePendingHashKey);
      if(EnableDuplicateFilter && IsProcessed(bridgePendingHash))
      {
         Print("[Bridge] Pending duplicate skipped");
         g_lastFilterReason = "Duplicate pending signal";
         return;
      }
      g_currentSignalHash = bridgePendingHash;
      g_trade.SetExpertMagicNumber(MagicNumber);

      // [v6.01 NEW] Multi-TP for Bridge JSON pending path -- parity with the
      // text-pending parser. Splits lots by LotDistribution % across pTP/tp2/tp3
      // legs and clamps the leg count by what lotsTotal can afford at minLot,
      // matching the same risk-budget guarantee as the text path.
      if(EnablePendingMultiTP && (tp2 > 0 || tp3 > 0))
      {
         double tpsJ[3]; tpsJ[0] = tp; tpsJ[1] = tp2; tpsJ[2] = tp3;

         int nTPs = 1 + (tp2 > 0 ? 1 : 0) + (tp3 > 0 ? 1 : 0);
         if(nTPs > MaxTPTargets) nTPs = MaxTPTargets;
         double legsJ[3]; legsJ[0] = 0; legsJ[1] = 0; legsJ[2] = 0;
         if(!TCU_BuildSignalTpLots(sym, lots, nTPs, legsJ[0], legsJ[1], legsJ[2], "Bridge"))
         {
            g_lastFilterReason = "SigTP lots invalid";
            return;
         }

        int placedJ = 0;
        for(int liJ2 = 0; liJ2 < nTPs; liJ2++)
        {
            if(!ArmExecution)
            {
               g_lastFilterReason = "DISARMED";
               Print("[Bridge] Pending placement aborted mid-flight -- EA was DISARMED before leg ", (liJ2+1));
               break;
            }
            double legTpJ = NormalizeDouble(tpsJ[liJ2], dg);
            string commentJ = TCU_TradeComment("TCU_pending_TP" + IntegerToString(liJ2 + 1));
            Print("[Bridge] Placing pending leg ", (liJ2+1), "/", nTPs, " ", sigType,
                  " ", sym, " lots=", DoubleToString(legsJ[liJ2], 2),
                  " @ ", pEntry, " SL:", sl, " TP:", legTpJ);
            if(g_trade.OrderOpen(sym, otype, legsJ[liJ2], 0, pEntry, sl, legTpJ,
                                 ORDER_TIME_GTC, 0, commentJ))
               placedJ++;
            else
               Print("[Bridge] Pending leg ", (liJ2+1), " failed: ", g_trade.ResultComment());
         }
         Print("[Bridge] Multi-TP pending placed legs: ", placedJ, "/", nTPs);
         if(placedJ > 0 && g_currentSignalHash != 0)
         {
            MarkProcessed(g_currentSignalHash);
            g_currentSignalHash = 0;
         }
         return;
      }

      Print("[Bridge] Placing pending ", sigType, " ", sym, " @ ", pEntry, " SL:", sl, " TP:", tp);
      // TODO: add STOP_LIMIT mapping here when the bridge payload supports separate stop-limit prices.
      if(!ArmExecution)
      {
         g_lastFilterReason = "DISARMED";
         Print("[Bridge] Pending placement aborted just before send -- EA is DISARMED: ", sigType);
         return;
      }
      if(g_trade.OrderOpen(sym, otype, lots, 0, pEntry, sl, tp, ORDER_TIME_GTC, 0, TCU_TradeComment("TCU_pending")))
      {
         if(g_currentSignalHash != 0)
         {
            MarkProcessed(g_currentSignalHash);
            g_currentSignalHash = 0;
         }
         Print("[Bridge] Pending placed: ", sigType, " ", sym, " @ ", pEntry);
      }
      else
         Print("[Bridge] Pending failed: ", g_trade.ResultComment());
      return;
   }
   
   // BREAKEVEN COMMAND
   if(dir == "BREAKEVEN")
   { if(StringLen(sym) > 0) sym = MapSym(sym); MoveToBreakeven(sym, "Bridge"); return; }

   // CLOSE COMMAND
   if(dir == "CLOSE")
   {
      string closeMsg = raw;
      if(StringLen(closeMsg) == 0)
      {
         if(StringLen(sym) > 0) closeMsg = "close " + sym;
         else closeMsg = "close all";
      }
      Print("[Bridge] Routing CLOSE payload to ProcessTextSig: ", StringSubstr(closeMsg, 0, 80));
      ProcessTextSig(closeMsg, srcName);
      return;
   }
   
   if(StringLen(dir) == 0 || StringLen(sym) == 0)
   { Print("[Bridge] Empty dir or sym"); return; }
   
   sym = MapSym(sym);
   if(IsNewsPauseActive(sym, true))
   {
      g_lastFilterReason = "News pause: " + g_tcuNewsLockReason;
      Print("[Bridge] Signal skipped by news pause: ", g_tcuNewsLockReason);
      return;
   }
   
   // Validate symbol
   string tradeSym = sym;
   if(SymbolInfoDouble(tradeSym, SYMBOL_BID) <= 0)
   {
      tradeSym = sym + SymbolSuffix;
      if(SymbolInfoDouble(tradeSym, SYMBOL_BID) <= 0)
      { Print("[Bridge] Symbol not found: ", sym); return; }
   }
   
   // Dedup: dir+sym+timestamp
   ulong hash = CalcHash(dir + sym + ts);
   if(EnableDuplicateFilter && IsProcessed(hash)) { Print("[Bridge] Duplicate skipped"); return; }
   // [v6.00 FIX 2026-04-26][R2] Defer hash persistence until ExecSignal succeeds.
   // Same rationale as the ProcessTextSig path: signals rejected by transient filters
   // (news pause, spread, margin, prop SL missing) must NOT be permanently locked out.
   g_currentSignalHash = hash;
   
   g_lastSignal = dir + " " + tradeSym + " [" + srcName + "]";
   g_signalsProcessed++;
   
    ExecSignal(dir, tradeSym, sl, tp, "Bridge", tp2, tp3, lot);
}

//+------------------------------------------------------------------+
string ExtractJsonStr(string json, string key)
{
   string srch = "\"" + key + "\"";
   int pos = StringFind(json, srch);
   if(pos < 0) return "";
   int cPos = StringFind(json, ":", pos + StringLen(srch));
   if(cPos < 0) return "";
   int n = StringLen(json);
   int v = cPos + 1;
   while(v < n)
   {
      ushort vc = StringGetCharacter(json, v);
      if(vc != ' ' && vc != '\t' && vc != '\r' && vc != '\n') break;
      v++;
   }
   // Value is not a string (null / number / object) -- nothing to extract.
   if(v >= n || StringGetCharacter(json, v) != '\"') return "";
   int qEnd = TCU_JsonStrEnd(json, v);
   if(qEnd <= v) return "";
   return TCU_JsonUnescape(StringSubstr(json, v + 1, qEnd - v - 1));
}

//+------------------------------------------------------------------+
double ExtractJsonDbl(string json, string key)
{
   string srch = "\"" + key + "\"";
   int pos = StringFind(json, srch);
   if(pos < 0) return 0;
   int cPos = StringFind(json, ":", pos);
   if(cPos < 0) return 0;
   int ns = cPos + 1, len = StringLen(json);
   while(ns < len)
   {
      ushort c = StringGetCharacter(json, ns);
      if(c >= 48 && c <= 57) break;
      if(c == 45) break;
      if(c == 110) return 0;
      ns++;
   }
   string numStr = "";
   while(ns < len)
   {
      ushort c = StringGetCharacter(json, ns);
      if((c >= 48 && c <= 57) || c == 46 || c == 45) numStr += ShortToString(c);
      else break;
      ns++;
   }
   return StringToDouble(numStr);
}

//+------------------------------------------------------------------+
void ClearBridgeSigs(bool broad = false)
{
   string url = "http://127.0.0.1:" + IntegerToString(BridgePort) + "/signals/clear/copier";
   int ackN = ArraySize(g_bridgeAckIds);

   // Targeted ACK: tell the bridge exactly which signal IDs we received this
   // poll, so a signal that arrived AFTER our GET is NOT cleared and gets
   // re-served next poll. `broad` (startup drain) or no captured IDs falls
   // back to legacy "{}" which the bridge treats as a full watermark.
   string body;
   if(broad || ackN <= 0)
   {
      body = "{}";
   }
   else
   {
      body = "{\"signal_ids\":[";
      for(int i = 0; i < ackN; i++)
      {
         if(i > 0) body += ",";
         body += IntegerToString(g_bridgeAckIds[i]);
      }
      body += "]}";
   }

   uchar post[], result[];
   StringToCharArray(body, post, 0, StringLen(body), CP_UTF8);
   string headers = "Content-Type: application/json\r\nX-NTS-Auth: " + NTS_AuthToken() + "\r\n"
                  + "X-Client-Id: " + NTS_ClientId() + "\r\n";
   string respHdr;
   WebRequest("POST", url, headers, 500, post, result, respHdr);

   ArrayResize(g_bridgeAckIds, 0);   // reset accumulator for the next poll
}

//+------------------------------------------------------------------+
void PollTelegram()
{
   if(StringLen(TelegramBotToken) < 10)
   {
      g_lastError = "BotAPI: No token set";
      return;
   }
   
   string url = TELEGRAM_URL + TelegramBotToken + "/getUpdates?offset=" + IntegerToString(g_lastUpdateId + 1) + "&timeout=0";
   char post[];
   char result[];
   string headers = "";
   
   ResetLastError();
   // [v6.00 FIX 2026-04-26][R3] WebRequest timeout 500ms -> 5000ms.
   // 500ms was too aggressive: api.telegram.org regularly responds 500-1500ms cross-region,
   // causing spurious failures + 30s exponential backoff that locked busy bots out for tens of seconds.
   // g_lastTelegramPoll interval guard already prevents tight spinning, so longer per-call timeout is safe.
   int res = WebRequest("GET", url, headers, 5000, post, result, headers);
   if(res != 200)
   {
      g_telegramFailCount++;
      int err = GetLastError();
      if(res == -1 && err == 4060)
         g_lastError = "BotAPI: Add https://api.telegram.org to WebRequest URLs";
      else if(res == -1)
         g_lastError = "BotAPI: WebRequest err " + IntegerToString(err);
      else
         g_lastError = "BotAPI: HTTP " + IntegerToString(res);
      // Backoff: log less frequently after repeated failures
      if(g_telegramFailCount <= 3 || g_telegramFailCount % 10 == 0)
         Print("[BotAPI] ", g_lastError, " (fail #", g_telegramFailCount, ")");
      return;
   }
   
   if(g_telegramFailCount > 0)
   {
      Print("[BotAPI] Connection restored after ", g_telegramFailCount, " failures");
      g_telegramFailCount = 0;
   }
   g_lastError = "";
   string response = CharArrayToString(result);
   ParseTgUpdates(response);
}

//+------------------------------------------------------------------+
void ParseTgUpdates(string json)
{
   int pos = 0;
   while(true)
   {
      int tPos = StringFind(json, "\"text\":\"", pos);
      if(tPos < 0) break;
      
      int uid = 0;  // Declare outside if block for later use
      int uPos = StringFind(json, "\"update_id\":", pos);
      if(uPos >= 0)
      {
         int uEnd = StringFind(json, ",", uPos + 12);
         if(uEnd < 0) uEnd = StringFind(json, "}", uPos + 12);
         string uStr = StringSubstr(json, uPos + 12, uEnd - uPos - 12);
         uid = (int)StringToInteger(uStr);
         if(uid <= g_lastUpdateId)
         {
            pos = tPos + 8;
            continue;
         }
         g_lastUpdateId = uid;
         SaveBotState();  // Persist state to prevent replaying on restart
      }
      
      int tStart = tPos + 8;
      int tEnd = StringFind(json, "\"", tStart);
      if(tEnd < 0) break;
      
      string msg = StringSubstr(json, tStart, tEnd - tStart);
      StringReplace(msg, "\\n", " ");

      string msgChatId = TCU_ExtractTelegramChatId(json, pos, tPos);
      if(StringLen(TelegramChatID) > 0 && StringLen(msgChatId) > 0 && msgChatId != TelegramChatID)
      {
         Print("[BotAPI] Skipped message from chat ", msgChatId, " (expected ", TelegramChatID, ")");
         pos = tEnd + 1;
         continue;
      }

      // [v6.01 CRITICAL FIX] Date-based old-message guard. Telegram includes a
      // Unix-timestamp "date" field on every message. If a message was sent
      // BEFORE this EA's bot-session started, drop it -- regardless of whether
      // the flush succeeded or update_id state looks correct. This is the
      // last-line defence against the "old signals replayed after fresh attach"
      // bug that real-money users hit on VPS deployments.
      bool isStaleMessage = false;
      bool isUndatedMessage = false;
      long msgDate = 0;
      {
         // Find the "date":N field that belongs to THIS message: it must be
         // located between the start of this update region (pos) and the
         // "text" field we already located (tPos).
         int dPos = StringFind(json, "\"date\":", pos);
         if(dPos >= 0 && dPos < tPos)
         {
            int dEnd = StringFind(json, ",", dPos + 7);
            if(dEnd < 0) dEnd = StringFind(json, "}", dPos + 7);
            if(dEnd > dPos + 7)
            {
               string dStr = StringSubstr(json, dPos + 7, dEnd - dPos - 7);
               msgDate = StringToInteger(dStr);
               long sessionStart = (long)g_botSessionStartTime - TCU_BOT_SESSION_TOLERANCE_SEC;
               if(msgDate > 0 && g_botSessionStartTime > 0 && msgDate < sessionStart)
               {
                  isStaleMessage = true;
               }
            }
         }
         // [v6.01 FAIL-SAFE] Telegram messages always include a "date" field;
         // if we couldn't parse it, our regex is broken or Telegram changed the
         // format. In either case, fail SAFE -- skip the message rather than
         // execute a trade we can't verify the age of. Better to miss a real
         // signal than to execute a stale one. The accompanying log line gives
         // us instant feedback if this ever fires in the wild.
         if(msgDate <= 0)
         {
            isUndatedMessage = true;
         }
      }

      if(isStaleMessage)
      {
         Print("[BotAPI] DROPPED stale message (msg_date=", msgDate,
               " session_start=", (long)g_botSessionStartTime,
               " age=", ((long)g_botSessionStartTime - msgDate), "s, uid=", uid, ")");
      }
      else if(isUndatedMessage)
      {
         Print("[BotAPI] DROPPED message with no parseable date field (uid=", uid,
               ") -- failing safe. If you see this repeatedly, Telegram JSON format may have changed.");
      }
      else if(!g_botFirstPollDone)
      {
         // Old messages are flushed at startup by FlushOldTelegramMessages().
         // If flush failed (WebRequest error), fall back to skipping first poll.
         Print("[BotAPI] Startup flush incomplete - skipping old message (update_id ", uid, ")");
      }
      else
      {
         ProcessTextSig(msg, "BotAPI");
         g_signalsProcessed++;
      }
      pos = tEnd + 1;
   }
   
   // After first poll completes, mark as done so next poll processes messages
   if(!g_botFirstPollDone)
   {
      g_botFirstPollDone = true;
      SaveBotState();
      Print("[BotAPI] First poll done -- old messages skipped. Now listening for NEW signals only.");
   }
}

//+------------------------------------------------------------------+
void CheckDiscord()
{
   // Legacy no-op: Discord polling was replaced by outbound webhook sending.
}

//+------------------------------------------------------------------+
void ProcessTextSig(string msg, string src)
{
   g_lastSignal = msg;
   DiagNew(msg, src);   // log every incoming signal to file before any filtering
   
   string uMsg = msg;
   StringToUpper(uMsg);
   // Strip TICKETS:xxx from uMsg so ticket numbers are never misread as SL/TP prices
   // by ExtractNum(). The ticket list is parsed from the original `msg` via ExtractTickets().
   {
      int tkPos = StringFind(uMsg, "TICKETS:");
      if(tkPos >= 0)
      {
         int tkEnd = tkPos + 8; // skip "TICKETS:"
         while(tkEnd < StringLen(uMsg))
         {
            ushort cc = StringGetCharacter(uMsg, tkEnd);
            if(cc == ' ' || cc == '\t' || cc == '\n' || cc == '\r') break;
            tkEnd++;
         }
         string tkToken = StringSubstr(uMsg, tkPos, tkEnd - tkPos);
         StringReplace(uMsg, tkToken, "");
      }
   }

   // KEYWORD REPLACE: Transform the uppercase parser buffer before parsing.
   // Doing this on raw mixed-case Telegram text is unreliable because
   // StringReplace() is case-sensitive and many providers vary casing.
   if(EnableKeywordReplace && StringLen(KeywordReplaceMap) > 0)
   {
      string kwPairs[];
      string kwMap = KeywordReplaceMap;
      StringToUpper(kwMap);
      int kwCount = StringSplit(kwMap, ',', kwPairs);
      for(int kw = 0; kw < kwCount; kw++)
      {
         string eqParts[];
         if(StringSplit(kwPairs[kw], '=', eqParts) == 2)
         {
            StringTrimLeft(eqParts[0]); StringTrimRight(eqParts[0]);
            StringTrimLeft(eqParts[1]); StringTrimRight(eqParts[1]);
            if((eqParts[0] == "TAKE" && eqParts[1] == "TP") ||
               (eqParts[0] == "STOP" && eqParts[1] == "SL") ||
               (eqParts[0] == "TP" && eqParts[1] == "TAKE") ||
               (eqParts[0] == "SL" && eqParts[1] == "STOP"))
               continue;
            if(StringLen(eqParts[0]) > 0) StringReplace(uMsg, eqParts[0], eqParts[1]);
         }
      }
      Print("[KW-REPLACE] After: ", StringSubstr(uMsg, 0, 80));
   }
   
   // ANTI-LOOP: Skip messages sent by this EA
   // Check 1: user-configured send tag
   string antiLoopTag = TelegramSendTag; StringToUpper(antiLoopTag);
   if(StringLen(antiLoopTag) > 0 && StringFind(uMsg, antiLoopTag) >= 0)
   { Print("[FILTER] Skipping own broadcast (anti-loop, tag match)"); return; }
   // Check 2: fixed permanent anti-loop marker (hardcoded, survives any tag/magic change)
   if(StringFind(uMsg, "NTS-BCT") >= 0)
   { Print("[FILTER] Skipping own broadcast (anti-loop, permanent marker)"); return; }
   // Check 3: structural pattern -- exclusively our broadcast format
   if(StringFind(uMsg, " ENTRY: ") >= 0 && StringFind(uMsg, " LOTS: ") >= 0)
   { Print("[FILTER] Skipping own broadcast (anti-loop, entry/lots pattern)"); return; }
   
   // SKIP KEYWORD FILTER: Built-in smart phrases (always active) + user custom keywords
   // This prevents status messages, commentary, promotions etc. from being treated as signals
   if(ContainsSkipKeyword(uMsg))
   {
      g_lastFilterReason = "Skip keyword match"; DiagLog("FILTERED","Skip keyword matched in message"); DiagSep();
      Print("[FILTER] Skipped non-signal message: ", StringSubstr(msg, 0, 60));
      return;
   }
   
   // COMMAND REPLIES: Handle close all / move sl / breakeven commands
   // OFF = ignore command-style messages completely.
   if(EnableCommandReplies)
   {
      // PARTIAL CLOSE detection (must run before full-close so "close half" never fires full-close)
      {
         bool isPartialClose = (StringFind(uMsg, "PARTIAL CLOSE") >= 0 || StringFind(uMsg, "CLOSE PARTIAL") >= 0 ||
                                StringFind(uMsg, "CLOSE HALF")   >= 0 || StringFind(uMsg, "HALF CLOSE")   >= 0 ||
                                StringFind(uMsg, "TAKE HALF")    >= 0 || StringFind(uMsg, "BOOK HALF")    >= 0 ||
                                StringFind(uMsg, "CLOSE 1/2")    >= 0 || StringFind(uMsg, "REDUCE POSITION") >= 0);
         int partPct = 50;
         if(!isPartialClose)
         {
            int cpPos = StringFind(uMsg, "CLOSE ");
            if(cpPos >= 0)
            {
               string cpTail = StringSubstr(uMsg, cpPos + 6, 8); StringTrimLeft(cpTail);
               string cpNum = "";
               for(int _ci = 0; _ci < StringLen(cpTail); _ci++)
               {
                  ushort _ch = StringGetCharacter(cpTail, _ci);
                  if(_ch >= '0' && _ch <= '9') cpNum += CharToString((uchar)_ch); else break;
               }
               int _pct = (int)StringToInteger(cpNum);
               if(_pct > 0 && _pct < 100 && StringFind(cpTail, "%") >= 0) { partPct = _pct; isPartialClose = true; }
            }
         }
         if(isPartialClose)
         {
            string prtSym = ExtractSym(uMsg); if(StringLen(prtSym) > 0) prtSym = MapSym(prtSym);
            ulong prtTkts[]; int prtTktCnt = ExtractTickets(msg, prtTkts);
            if(prtTktCnt < 0) { Print("[CMD] Partial close skipped - positions already closed"); return; }
            Print("[CMD] Partial close ", partPct, "% sym=", prtSym, " tickets=", prtTktCnt);
            int prtDone = 0;
            for(int _pp = PositionsTotal() - 1; _pp >= 0; _pp--)
            {
               ulong _tktP = PositionGetTicket(_pp); if(_tktP == 0) continue;
               if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
               if(!TicketInList(_tktP, prtTkts, prtTktCnt)) continue;
               if(StringLen(prtSym) > 0 && PositionGetString(POSITION_SYMBOL) != prtSym) continue;
               double _vol = PositionGetDouble(POSITION_VOLUME);
               double _closeVol = NormalizeDouble(_vol * partPct / 100.0, 2);
               string _pSym = PositionGetString(POSITION_SYMBOL);
               double _minLot = SymbolInfoDouble(_pSym, SYMBOL_VOLUME_MIN);
               if(_closeVol < _minLot) _closeVol = _minLot;
               if(_closeVol >= _vol) g_trade.PositionClose(_tktP);
               else g_trade.PositionClosePartial(_tktP, _closeVol);
               prtDone++;
            }
            Print("[CMD] Partial close done: ", prtDone, " position(s) at ", partPct, "%");
            DoAlert("Partial close " + IntegerToString(partPct) + "%: " + IntegerToString(prtDone) + " position(s)");
            return;
         }
      }

      // CLOSE detection: CLOSE ALL, CLOSE POSITION, CLOSE TRADE, or CLOSE <symbol> (e.g. "close gold", "close EURUSD")
      int cPos = WordFind(uMsg, "CLOSE");
      if(cPos < 0) cPos = WordFind(uMsg, "EXIT");
      if(cPos < 0 && StringFind(uMsg, "GET OUT") >= 0) cPos = StringFind(uMsg, "GET OUT");
      if(cPos < 0 && StringFind(uMsg, "OUT NOW") >= 0) cPos = StringFind(uMsg, "OUT NOW");
      if(cPos < 0 && StringFind(uMsg, "MANUAL CLOSE") >= 0) cPos = StringFind(uMsg, "MANUAL CLOSE");
      bool isCloseSym = false;
      string closeSymCheck = "";
      if(cPos >= 0)
      {
         if(cPos >= 3)
         {
            string before = StringSubstr(uMsg, MathMax(0, cPos - 15), 15);
            if(StringFind(before, "NEAR ") >= 0 || StringFind(before, "BEFORE ") >= 0 ||
               StringFind(before, "AFTER ") >= 0 || StringFind(before, "AT ") >= 0 ||
               StringFind(before, "APPROACH") >= 0 || StringFind(before, "BY ") >= 0)
               cPos = -1;
         }
      }
      if(cPos >= 0)
      {
         string tail = StringSubstr(uMsg, cPos, 40);
         closeSymCheck = ExtractSym(tail);
         isCloseSym = (StringLen(closeSymCheck) > 0);
      }
      if(StringFind(uMsg, "CLOSE ALL") >= 0 || StringFind(uMsg, "CLOSE POSITION") >= 0 || StringFind(uMsg, "CLOSE TRADE") >= 0 ||
         StringFind(uMsg, "CLOSE NOW") >= 0 || StringFind(uMsg, "EXIT ALL") >= 0 || StringFind(uMsg, "EXIT NOW") >= 0 ||
         StringFind(uMsg, "EXIT TRADE") >= 0 || StringFind(uMsg, "EXIT POSITION") >= 0 ||
         StringFind(uMsg, "GET OUT") >= 0 || StringFind(uMsg, "OUT NOW") >= 0 || StringFind(uMsg, "MANUAL CLOSE") >= 0 || isCloseSym)
      {
         // Smart close: detect symbol and direction from the message
         string closeSym = closeSymCheck;
         if(StringLen(closeSym) > 0) closeSym = MapSym(closeSym);
         
         // Detect if message specifies BUY or SELL direction to close
         bool closeOnlyBuy = false, closeOnlySell = false;
         if(WordFind(uMsg, "BUY") >= 0 && WordFind(uMsg, "SELL") < 0) closeOnlyBuy = true;
         if(WordFind(uMsg, "SELL") >= 0 && WordFind(uMsg, "BUY") < 0) closeOnlySell = true;
         
         string closeDesc = "Close";
         if(closeOnlyBuy) closeDesc += " BUY";
         if(closeOnlySell) closeDesc += " SELL";
         if(StringLen(closeSym) > 0) closeDesc += " " + closeSym;
         else closeDesc += " ALL";
         ulong closeTickets[]; int closeTicketCount = ExtractTickets(msg, closeTickets);
         if(closeTicketCount < 0) { Print("[CMD] Close skipped - all positions for this signal already closed"); return; }
         Print("[CMD] ", closeDesc, " command detected from: ", src, " tickets=", closeTicketCount);
         
         int closed = 0;
         for(int p5 = PositionsTotal() - 1; p5 >= 0; p5--)
         {
            ulong tkt5 = PositionGetTicket(p5);
            if(tkt5 > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
               // Filter by ticket list if provided (from bridge TICKETS: tag)
               if(!TicketInList(tkt5, closeTickets, closeTicketCount)) continue;
               // Filter by symbol if specified
               if(StringLen(closeSym) > 0 && PositionGetString(POSITION_SYMBOL) != closeSym) continue;
               // Filter by direction if specified
               if(closeOnlyBuy && (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
               if(closeOnlySell && (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
               
               g_trade.PositionClose(tkt5);
               closed++;
            }
         }
         Print("[CMD] Closed ", closed, " positions (", closeDesc, ")");
         DoAlert(closeDesc + ": " + IntegerToString(closed) + " positions closed");
         return;
      }
      
      // Custom close commands from CloseAllCommands input (uses same smart filtering)
      string closeCmds2[];
      string closeList2 = CloseAllCommands;
      int closeCount2 = StringSplit(closeList2, ',', closeCmds2);
      for(int cc = 0; cc < closeCount2; cc++)
      {
         string ccmd = closeCmds2[cc]; StringTrimLeft(ccmd); StringTrimRight(ccmd); StringToUpper(ccmd);
         if(StringLen(ccmd) > 0 && StringFind(uMsg, ccmd) >= 0)
         {
            string cSym = ExtractSym(uMsg);
            if(StringLen(cSym) > 0) cSym = MapSym(cSym);
            Print("[CMD] Custom close command: ", closeCmds2[cc], " sym=", cSym);
            int closed2 = 0;
            for(int p5b = PositionsTotal() - 1; p5b >= 0; p5b--)
            {
               if(PositionGetTicket(p5b) > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
               {
                  if(StringLen(cSym) > 0 && PositionGetString(POSITION_SYMBOL) != cSym) continue;
                  g_trade.PositionClose(PositionGetTicket(p5b));
                  closed2++;
               }
            }
            DoAlert("Close: " + IntegerToString(closed2) + " positions closed");
            return;
         }
      }
      
      // SET SL / SET TP to a specific price level
      // Handles: "move sl 2500", "set sl 2500", "set stoploss @2500", "sl @2500",
      //          "set tp 5000", "move tp 5000", "take profit 5000", etc.
      // Must run BEFORE the MOVE SL → breakeven path so "move sl 2500" is not
      // misclassified as a breakeven command. Only fires when a valid price is
      // present and there is no BUY/SELL keyword (i.e. not a new trade signal).
      bool hasNewDir = (WordFind(uMsg, "BUY") >= 0 || WordFind(uMsg, "SELL") >= 0);
      if(!hasNewDir)
      {
         bool hasSLcmd = (StringFind(uMsg, "MOVE SL")    >= 0 || StringFind(uMsg, "SET SL")      >= 0 ||
                          StringFind(uMsg, "STOPLOSS")   >= 0 || StringFind(uMsg, "STOP LOSS")   >= 0 ||
                          StringFind(uMsg, "MOVE STOP")  >= 0 || StringFind(uMsg, "CHANGE SL")   >= 0 ||
                          StringFind(uMsg, "ADJUST SL")  >= 0 || StringFind(uMsg, "NEW SL")      >= 0 ||
                          StringFind(uMsg, "TIGHTEN SL") >= 0 || StringFind(uMsg, "TRAIL STOP")  >= 0 ||
                          StringFind(uMsg, "TRAIL SL")   >= 0);
         bool hasTPcmd = (StringFind(uMsg, "MOVE TP")    >= 0 || StringFind(uMsg, "SET TP")      >= 0 ||
                          StringFind(uMsg, "TAKEPROFIT") >= 0 || StringFind(uMsg, "TAKE PROFIT") >= 0 ||
                          StringFind(uMsg, "CHANGE TP")  >= 0 || StringFind(uMsg, "NEW TP")      >= 0 ||
                          StringFind(uMsg, "ADJUST TP")  >= 0);

         double setSL = 0, setTP = 0;
         if(hasSLcmd)
         {
            setSL = ExtractNum(uMsg, "SL");
            if(setSL == 0) setSL = ExtractNum(uMsg, "STOPLOSS");
            if(setSL == 0) setSL = ExtractNum(uMsg, "STOP LOSS");
            if(setSL == 0) setSL = ExtractNum(uMsg, "STOP");
         }
         if(hasTPcmd)
         {
            setTP = ExtractNum(uMsg, "TP");
            if(setTP == 0) setTP = ExtractNum(uMsg, "TAKEPROFIT");
            if(setTP == 0) setTP = ExtractNum(uMsg, "TAKE PROFIT");
         }

         if(setSL > 0 || setTP > 0)
         {
            string modSym = ExtractSym(uMsg);
            if(StringLen(modSym) > 0) modSym = MapSym(modSym);
            ulong modTickets[]; int modTicketCount = ExtractTickets(msg, modTickets);
            if(modTicketCount < 0) { Print("[CMD] Modify skipped - all positions for this signal already closed"); return; }
            Print("[CMD] Modify SL/TP: SL=", setSL, " TP=", setTP, " sym=", modSym, " src=", src, " tickets=", modTicketCount);
            int modCount = 0;
            for(int pm = PositionsTotal() - 1; pm >= 0; pm--)
            {
               ulong tktM = PositionGetTicket(pm);
               if(tktM == 0) continue;
               if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
               if(!TicketInList(tktM, modTickets, modTicketCount)) continue;
               string posSym = PositionGetString(POSITION_SYMBOL);
               if(StringLen(modSym) > 0 && posSym != modSym) continue;
               int digM = (int)SymbolInfoInteger(posSym, SYMBOL_DIGITS);
               double curSLm = PositionGetDouble(POSITION_SL);
               double curTPm = PositionGetDouble(POSITION_TP);
               double newSLm = (setSL > 0) ? NormalizeDouble(setSL, digM) : curSLm;
               double newTPm = (setTP > 0) ? NormalizeDouble(setTP, digM) : curTPm;
               if(g_trade.PositionModify(tktM, newSLm, newTPm))
               {
                  Print("[CMD] Modified #", tktM, " ", posSym, " SL=", DoubleToString(newSLm, digM), " TP=", DoubleToString(newTPm, digM));
                  modCount++;
               }
               else
                  Print("[CMD] Modify failed #", tktM, " - ", g_trade.ResultComment());
            }
            Print("[CMD] Modify SL/TP done: ", modCount, " position(s)");
            if(modCount > 0)
               DoAlert(src + ": SL/TP modified on " + IntegerToString(modCount) + " position(s)");
            return;
         }
      }

      // MOVE SL / BREAKEVEN detection (built-in)
      // Only reaches here when no specific SL price was found above.
      if(StringFind(uMsg, "MOVE SL")       >= 0 || StringFind(uMsg, "MOVE STOP")    >= 0 ||
         StringFind(uMsg, "BREAKEVEN")      >= 0 || StringFind(uMsg, "BREAK EVEN")   >= 0 ||
         StringFind(uMsg, "SL TO BE")       >= 0 || StringFind(uMsg, "SL TO ENTRY")  >= 0 ||
         StringFind(uMsg, "RISK FREE")      >= 0 || StringFind(uMsg, "RISK-FREE")    >= 0 ||
         StringFind(uMsg, "NO RISK")        >= 0 || StringFind(uMsg, "SECURE PROFIT") >= 0 ||
         StringFind(uMsg, "LOCK PROFIT")    >= 0 || StringFind(uMsg, "PROTECT TRADE") >= 0 ||
         StringFind(uMsg, "MOVE TO ENTRY")  >= 0)
      {
         string beSym = ExtractSym(uMsg);
         if(StringLen(beSym) > 0) beSym = MapSym(beSym);
         ulong beTickets[]; int beTicketCount = ExtractTickets(msg, beTickets);
         if(beTicketCount < 0) { Print("[CMD] Breakeven skipped - all positions for this signal already closed"); return; }
         Print("[CMD] Breakeven command detected from: ", src, " tickets=", beTicketCount);
         MoveToBreakevenFiltered(beSym, src, beTickets, beTicketCount);
         return;
      }
      
      // Custom move SL commands from MoveSLCommands input
      string moveCmds[];
      string moveList = MoveSLCommands;
      int moveCount = StringSplit(moveList, ',', moveCmds);
      for(int mc = 0; mc < moveCount; mc++)
      {
         string mcmd = moveCmds[mc]; StringTrimLeft(mcmd); StringTrimRight(mcmd); StringToUpper(mcmd);
         if(StringLen(mcmd) > 0 && StringFind(uMsg, mcmd) >= 0)
         {
            string beSym2 = ExtractSym(uMsg);
            if(StringLen(beSym2) > 0) beSym2 = MapSym(beSym2);
            MoveToBreakeven(beSym2, "CMD");
            return;
         }
      }

      // CANCEL PENDING ORDERS
      if(StringFind(uMsg, "CANCEL PENDING") >= 0 || StringFind(uMsg, "CANCEL ORDER") >= 0 ||
         StringFind(uMsg, "DELETE PENDING") >= 0 || StringFind(uMsg, "REMOVE PENDING") >= 0)
      {
         // SAFETY: Bridge injects TICKETS:NONE for standalone cancel commands
         // that have no proven reply target. ExtractTickets() returns -1 for
         // TICKETS:NONE -- we MUST honor it. Cancelling every pending order
         // for our magic number on a standalone command is unsafe (it would
         // delete unrelated pending orders the user did not intend to touch).
         ulong cancelTickets[]; int cancelTicketCount = ExtractTickets(msg, cancelTickets);
         if(cancelTicketCount < 0) {
            Print("[CMD] Cancel pending skipped - TICKETS:NONE (no proven reply target)");
            return;
         }
         string canSym = ExtractSym(uMsg); if(StringLen(canSym) > 0) canSym = MapSym(canSym);
         int cancelled = 0;
         for(int _po = OrdersTotal() - 1; _po >= 0; _po--)
         {
            ulong _oTkt = OrderGetTicket(_po); if(_oTkt == 0) continue;
            if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
            if(StringLen(canSym) > 0 && OrderGetString(ORDER_SYMBOL) != canSym) continue;
            // Filter by ticket list if Bridge provided one (proven reply path)
            if(cancelTicketCount > 0 && !TicketInList(_oTkt, cancelTickets, cancelTicketCount)) continue;
            if(g_trade.OrderDelete(_oTkt)) cancelled++;
         }
         Print("[CMD] Cancelled ", cancelled, " pending order(s) sym=", canSym);
         DoAlert("Cancel pending: " + IntegerToString(cancelled) + " order(s) cancelled");
         return;
      }
   }
   
   
   double signalLots = ExtractNum(uMsg, "LOTS");
   if(signalLots == 0) signalLots = ExtractNum(uMsg, "LOT");
   if(signalLots == 0) signalLots = ExtractNum(uMsg, "VOLUME");
   if(signalLots < 0 || signalLots > 1000) signalLots = 0;

   // PENDING ORDER DETECTION: BUY LIMIT, SELL LIMIT, BUY STOP, SELL STOP
   // Must check BEFORE isBuy/isSell because "BUY LIMIT" contains "BUY"
   string pendingType = "";
   if(StringFind(uMsg, "BUY STOP LIMIT") >= 0)       pendingType = "BUY_STOP_LIMIT";
   else if(StringFind(uMsg, "SELL STOP LIMIT") >= 0)  pendingType = "SELL_STOP_LIMIT";
   else if(StringFind(uMsg, "BUY LIMIT") >= 0)        pendingType = "BUY_LIMIT";
   else if(StringFind(uMsg, "SELL LIMIT") >= 0)       pendingType = "SELL_LIMIT";
   else if(WordFind(uMsg, "BUY STOP") >= 0)           pendingType = "BUY_STOP";   // WordFind prevents matching BUY STOPLOSS
   else if(WordFind(uMsg, "SELL STOP") >= 0)          pendingType = "SELL_STOP";  // WordFind prevents matching SELL STOPLOSS
   
    if(StringLen(pendingType) > 0)
    {
       if(!EnablePendingOrders)
       {
          Print("[FILTER] Pending order signal ignored (EnablePendingOrders=false): ", pendingType, " | ", StringSubstr(msg, 0, 60));
          return;
       }
       if(!ArmExecution)
       {
          g_lastFilterReason = "DISARMED";
          Print("[PENDING] DISARMED -- pending signal received but NOT placing order.");
          DiagLog("BLOCKED", "DISARMED pending order");
          DiagSep();
          return;
       }
       if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
       {
          string why = !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
                       ? "AutoTrading is OFF in MT5 toolbar -- click the AutoTrading button"
                       : "AlgoTrading disabled for this EA -- enable in EA properties (Common tab)";
          g_lastFilterReason = why;
          Print("[PENDING] Rejected -- ", why);
          return;
       }

       // [v6.01 FIX] Daily-loss kill-switch on the pending-order path. Previously
      // only the market-order path (ExecSignal) gated on this. A pending order
      // placed after the daily limit was hit could fill later and push the
      // account further into the red.
      if(IsDailyLossLimitHit())
      {
         g_lastFilterReason = "Daily loss limit hit (pending)";
         Print("[FILTER] Pending order rejected -- daily loss limit hit: ", pendingType, " | ", StringSubstr(msg, 0, 60));
         return;
      }

      // [v6.01 FIX] Max open positions cap on the pending-order path. Counts
      // BOTH live positions AND unfilled pendings -- otherwise a user with
      // MaxOpenPositions=20 could stack 20 pendings on top of 20 positions and
      // end up with 40 trades when the pendings fill.
      int effectivePendMaxOpen = TCU_EffectiveMaxOpenPositions();
      if(effectivePendMaxOpen > 0 && (PositionsTotal() + OrdersTotal()) >= effectivePendMaxOpen)
      {
         g_lastFilterReason = "Max open positions reached (pending)";
         Print("[FILTER] Pending rejected -- positions+pendings (", PositionsTotal(), "+", OrdersTotal(), ") >= cap (", effectivePendMaxOpen, ")");
         return;
      }

      // Extract symbol, entry price, SL, TP for pending order
      string pSym = ExtractSym(uMsg);
      if(StringLen(pSym) == 0) { Print("[FILTER] Pending: no symbol found, skipping"); return; }
      pSym = MapSym(pSym);
      // Pending orders return before the normal text dedup block later in
      // ProcessTextSig(), so they need their own hash guard here.
      ulong pendingHash = CalcHash(uMsg);
      if(EnableDuplicateFilter && IsProcessed(pendingHash))
      {
         g_lastFilterReason = "Duplicate pending signal";
         DiagLog("BLOCKED", "Duplicate pending -- hash already processed");
         DiagSep();
         Print("[PENDING] Duplicate pending signal ignored");
         return;
      }
      g_currentSignalHash = pendingHash;
       if(IsNewsPauseActive(pSym, true))
       {
          g_lastFilterReason = "News pause: " + g_tcuNewsLockReason;
          Print("[FILTER] Pending skipped by news pause: ", g_tcuNewsLockReason);
          return;
       }
       if(!IsSymbolAllowed(pSym))
       {
          g_lastFilterReason = "Symbol filter";
          Print("[FILTER] Pending symbol ", pSym, " blocked by whitelist/blacklist. Skipping.");
          return;
       }
       
       double pEntry = ExtractNum(uMsg, "ENTRY");
      if(pEntry == 0) pEntry = ExtractNum(uMsg, "@");
      if(pEntry == 0) pEntry = ExtractNum(uMsg, "PRICE");
      if(pEntry == 0) pEntry = ExtractNum(uMsg, "AT");           // catches "buy limit AT 5000"
      if(pEntry == 0) pEntry = ExtractNum(uMsg, "LIMIT");        // catches "buy LIMIT 5000"
      if(pEntry == 0) pEntry = ExtractNum(uMsg, "STOP");         // catches "buy STOP 5000"
      if(pEntry == 0) pEntry = ExtractNum(uMsg, "ZONE");
      // Try extracting a number right after the pending type keyword
      if(pEntry == 0) pEntry = ExtractNum(uMsg, pendingType);
      // Last resort: look for the first standalone number in the message
      // This catches bare formats like "gold buy limit 6500"
      if(pEntry == 0)
      {
         string tmp = uMsg;
         // Strip known keyword tokens so we don't grab their trailing digits
         StringReplace(tmp, "BUY LIMIT", ""); StringReplace(tmp, "SELL LIMIT", "");
         StringReplace(tmp, "BUY STOP", "");  StringReplace(tmp, "SELL STOP", "");
         StringReplace(tmp, "BUY", "");        StringReplace(tmp, "SELL", "");
         int tLen = StringLen(tmp);
         for(int ci = 0; ci < tLen; ci++)
         {
            ushort cc = StringGetCharacter(tmp, ci);
            if(cc >= '0' && cc <= '9')
            {
               string numBuf = "";
               while(ci < tLen)
               {
                  ushort nc = StringGetCharacter(tmp, ci);
                  if((nc >= '0' && nc <= '9') || nc == '.') { numBuf += ShortToString(nc); ci++; }
                  else break;
               }
               double candidate = StringToDouble(numBuf);
               if(candidate > 0.001) { pEntry = candidate; break; }
            }
         }
      }
      
      // RANGE ENTRY FIX: Handle "5162-5163" format -- direction-aware pick.
      // [v6.01 FIX] BUY pendings take the lower bound (deeper pullback for
      // better entry on a buy). SELL pendings take the upper bound (higher
      // sell for a short). The legacy code always took MathMin which made
      // SELL LIMIT range orders enter at the *worse* price -- a real
      // money-leak on every multi-price-zone sell signal.
      if(pEntry == 0)
      {
         bool rangeIsBuy = (StringFind(pendingType, "BUY") >= 0);
         // Scan for pattern: digits-digits (e.g. 5162-5163 or 1.0830-1.0840)
         int msgLen2 = StringLen(uMsg);
         for(int ri2 = 1; ri2 < msgLen2 - 1 && pEntry == 0; ri2++)
         {
            ushort rch = StringGetCharacter(uMsg, ri2);
            if(rch == '-')
            {
               ushort rb = StringGetCharacter(uMsg, ri2 - 1);
               ushort ra = StringGetCharacter(uMsg, ri2 + 1);
               if((rb >= '0' && rb <= '9') && (ra >= '0' && ra <= '9'))
               {
                  // Extract left number
                  int ls = ri2 - 1;
                  while(ls > 0) { ushort c2 = StringGetCharacter(uMsg, ls-1); if((c2>='0'&&c2<='9')||c2=='.') ls--; else break; }
                  string lNum = StringSubstr(uMsg, ls, ri2 - ls);
                  // Extract right number
                  int re2 = ri2 + 1;
                  string rNum = "";
                  while(re2 < msgLen2) { ushort c3 = StringGetCharacter(uMsg, re2); if((c3>='0'&&c3<='9')||c3=='.'){rNum+=ShortToString(c3);re2++;} else break; }
                  double lo = StringToDouble(lNum), hi = StringToDouble(rNum);
                  if(lo > 0.001 && hi > 0.001)
                  {
                     pEntry = rangeIsBuy ? MathMin(lo, hi) : MathMax(lo, hi);
                     Print("[PENDING] Range entry detected: ", lNum, "-", rNum,
                           " -> using ", (rangeIsBuy ? "lowest" : "highest"),
                           " for ", (rangeIsBuy ? "BUY" : "SELL"), ": ", pEntry);
                  }
               }
            }
         }
      }
      
      if(pEntry == 0)
      {
         Print("[FILTER] Pending order missing entry price, skipping: ", StringSubstr(msg, 0, 80));
         return;
      }
      
      double pSL = 0, pTP = 0;
      if(CopySL)
      {
         pSL = ExtractNum(uMsg, "SL");
         if(pSL == 0) pSL = ExtractNum(uMsg, "STOPLOSS");
         if(pSL == 0) pSL = ExtractNum(uMsg, "STOP LOSS");
         if(pSL == 0) pSL = ExtractNum(uMsg, "S/L");
         if(pSL == 0) pSL = ExtractNum(uMsg, "S.L.");
         if(pSL == 0 && EnableCustomSLTPKeywords) pSL = ExtractNumCustom(uMsg, CustomSLKeywords);
         if(pSL > 0 && TCU_MessageUsesRelativeSL(uMsg))
         {
            Print("[FILTER] Pending signal uses relative SL wording (pips/points). Relative SL/TP mode is not supported here, so SL will be ignored.");
            g_lastError = "Relative SL wording not supported";
            pSL = 0;
         }
      }
      if(CopyTP && EnableSignalTP)
      {
         pTP = ExtractNum(uMsg, "TP1");
         if(pTP == 0) pTP = ExtractNum(uMsg, "TP");
         if(pTP == 0) pTP = ExtractNum(uMsg, "TAKE PROFIT");
         if(pTP == 0) pTP = ExtractNum(uMsg, "T/P");
         if(pTP == 0) pTP = ExtractNum(uMsg, "TARGET");
         if(pTP == 0 && EnableCustomSLTPKeywords) pTP = ExtractNumCustom(uMsg, CustomTPKeywords);
         // Sequential bare TP scan for pending orders too
         if(pTP == 0)
         {
            int sp2 = 0; int mLen2 = StringLen(uMsg);
            while(sp2 < mLen2 - 2)
            {
               int tp2pos = StringFind(uMsg, "TP", sp2);
               if(tp2pos < 0) break;
               ushort nch2 = (tp2pos+2 < mLen2) ? StringGetCharacter(uMsg, tp2pos+2) : 0;
               ushort pch2 = (tp2pos > 0) ? StringGetCharacter(uMsg, tp2pos-1) : ' ';
               bool ndig2 = (nch2 >= '0' && nch2 <= '9');
               bool plet2 = ((pch2 >= 'A' && pch2 <= 'Z') || (pch2 >= 'a' && pch2 <= 'z'));
               if(!ndig2 && !plet2)
               {
                  int ns2 = tp2pos + 2;
                  while(ns2 < mLen2 && (StringGetCharacter(uMsg,ns2)==' '||StringGetCharacter(uMsg,ns2)==':')) ns2++;
                  string nb2 = ""; int ni2 = ns2;
                  while(ni2 < mLen2) { ushort nc2 = StringGetCharacter(uMsg,ni2); if((nc2>='0'&&nc2<='9')||nc2=='.'){nb2+=ShortToString(nc2);ni2++;} else break; }
                  double tv2 = StringToDouble(nb2);
                  if(tv2 > 0.001) { pTP = tv2; break; }
               }
               sp2 = tp2pos + 2;
            }
         }
      }
      
       bool pIsBuy = (StringFind(pendingType, "BUY") >= 0);
       string pDir = pIsBuy ? "BUY" : "SELL";
       if(ReverseSignal)
       {
          if(pDir == "BUY")
          {
             pDir = "SELL";
             StringReplace(pendingType, "BUY", "SELL");
          }
          else
          {
             pDir = "BUY";
             StringReplace(pendingType, "SELL", "BUY");
          }
          pIsBuy = (pDir == "BUY");
          Print("[PENDING] ReverseSignal applied -- using ", pendingType);
       }
       ENUM_ORDER_TYPE orderType;
      double pStopLimit = 0;
      if(pendingType == "BUY_LIMIT") orderType = ORDER_TYPE_BUY_LIMIT;
      else if(pendingType == "SELL_LIMIT") orderType = ORDER_TYPE_SELL_LIMIT;
      else if(pendingType == "BUY_STOP") orderType = ORDER_TYPE_BUY_STOP;
      else if(pendingType == "SELL_STOP") orderType = ORDER_TYPE_SELL_STOP;
      else if(pendingType == "BUY_STOP_LIMIT") orderType = ORDER_TYPE_BUY_STOP_LIMIT;
      else if(pendingType == "SELL_STOP_LIMIT") orderType = ORDER_TYPE_SELL_STOP_LIMIT;
      else { Print("[FILTER] Unknown pending type: ", pendingType); return; }

      if(pendingType == "BUY_STOP_LIMIT" || pendingType == "SELL_STOP_LIMIT")
      {
         double pTrig = ExtractNumLast(uMsg, "STOP");
         double pLim  = ExtractNumLast(uMsg, "LIMIT");
         if(pTrig <= 0 || pLim <= 0)
         {
            Print("[PENDING] STOP_LIMIT requires both STOP and LIMIT prices - skipping: ", StringSubstr(msg, 0, 80));
            g_lastFilterReason = "STOP_LIMIT needs 2 prices";
            return;
         }
         pStopLimit = pTrig;
         pEntry = pLim;
      }
      
      // Extract TP2/TP3 for pending multi-TP (sequential bare TP or numbered targets)
      double pTP2 = 0, pTP3 = 0;
      if(EnablePendingMultiTP && CopyTP && EnableSignalTP)
      {
         pTP2 = ExtractNum(uMsg, "TP2");
         if(pTP2 == 0) pTP2 = ExtractNum(uMsg, "T2");
         if(pTP2 == 0) pTP2 = ExtractNum(uMsg, "TARGET 2");
         pTP3 = ExtractNum(uMsg, "TP3");
         if(pTP3 == 0) pTP3 = ExtractNum(uMsg, "T3");
         if(pTP3 == 0) pTP3 = ExtractNum(uMsg, "TARGET 3");
         // Sequential bare TP scan: collect all bare-TP values in order
         if(pTP2 == 0 || pTP3 == 0)
         {
            double tpListP[10]; int tpCntP = 0;
            int spP = 0; int mLenP = StringLen(uMsg);
            while(spP < mLenP - 2 && tpCntP < 10)
            {
               int tpPosP = StringFind(uMsg, "TP", spP);
               if(tpPosP < 0) break;
               ushort nchP = (tpPosP+2 < mLenP) ? StringGetCharacter(uMsg, tpPosP+2) : 0;
               ushort pchP = (tpPosP > 0) ? StringGetCharacter(uMsg, tpPosP-1) : ' ';
               bool ndigP = (nchP >= '0' && nchP <= '9');
               bool pletP = ((pchP >= 'A' && pchP <= 'Z') || (pchP >= 'a' && pchP <= 'z'));
               if(!ndigP && !pletP)
               {
                  int nsP = tpPosP + 2;
                  while(nsP < mLenP && (StringGetCharacter(uMsg,nsP)==' '||StringGetCharacter(uMsg,nsP)==':')) nsP++;
                  string nbP = ""; int niP = nsP;
                  while(niP < mLenP) { ushort ncP = StringGetCharacter(uMsg,niP); if((ncP>='0'&&ncP<='9')||ncP=='.'){nbP+=ShortToString(ncP);niP++;} else break; }
                  double tvP = StringToDouble(nbP);
                  if(tvP > 0.001) tpListP[tpCntP++] = tvP;
               }
               spP = tpPosP + 2;
            }
            if(tpCntP >= 1 && pTP == 0)  pTP  = tpListP[0];
            if(tpCntP >= 2 && pTP2 == 0) pTP2 = tpListP[1];
            if(tpCntP >= 3 && pTP3 == 0) pTP3 = tpListP[2];
         }
      }
      if((pTP > 0 || pTP2 > 0 || pTP3 > 0) && TCU_MessageUsesRelativeTP(uMsg))
      {
         Print("[FILTER] Pending signal uses relative TP wording (pips/points). Relative SL/TP mode is not supported here, so all signal TPs will be ignored.");
         g_lastError = "Relative TP wording not supported";
         pTP = 0; pTP2 = 0; pTP3 = 0;
      }
      
      // [v6.01 FIX] Calculate lot size -- direction-aware (BID for SELL).
      // pIsBuy was already computed above when we determined orderType.
      double lotsTotal = CalcLots(pSym, pSL, signalLots, pIsBuy ? "BUY" : "SELL", pTP);
      if(SkipIfLotOverMax && lotsTotal > MaxLotSize)
      {
         Print("[PENDING] Lot too large - skipping: ", DoubleToString(lotsTotal, 2), " > ", DoubleToString(MaxLotSize, 2));
         g_lastFilterReason = "Lot > max";
         return;
      }
       int digits = (int)SymbolInfoInteger(pSym, SYMBOL_DIGITS);
       if(pStopLimit > 0) pStopLimit = NormalizeDouble(pStopLimit, digits);
       pEntry = NormalizeDouble(pEntry, digits);
       if(pSL  > 0) pSL  = NormalizeDouble(pSL,  digits);
       if(pTP  > 0) pTP  = NormalizeDouble(pTP,  digits);
       if(pTP2 > 0) pTP2 = NormalizeDouble(pTP2, digits);
       if(pTP3 > 0) pTP3 = NormalizeDouble(pTP3, digits);
       double pipSize = PipSize(pSym);
       if(EnableAutoSL && pSL <= 0 && FallbackSLPips > 0)
       {
          pSL = pIsBuy ? (pEntry - FallbackSLPips * pipSize) : (pEntry + FallbackSLPips * pipSize);
          pSL = NormalizeDouble(pSL, digits);
          Print("[PENDING] Using Auto SL: ", DoubleToString(pSL, digits));
       }
       if(EnableAutoTP && pTP <= 0 && FallbackTPPips > 0)
       {
          pTP = pIsBuy ? (pEntry + FallbackTPPips * pipSize) : (pEntry - FallbackTPPips * pipSize);
          pTP = NormalizeDouble(pTP, digits);
          Print("[PENDING] Using Auto TP: ", DoubleToString(pTP, digits));
       }
       if(PropFirmMode && pSL <= 0)
       {
          g_lastFilterReason = "PropFirm: SL required";
          Print("[PENDING] Rejected -- PropFirmMode requires SL after fallback: ", pendingType, " ", pSym);
          return;
       }
       if(SkipSignalWithoutSL && pSL <= 0)
       {
          g_lastFilterReason = "No SL (pending)";
          Print("[PENDING] No SL - skipping");
          return;
       }
       if(SkipSignalWithoutTP && pTP <= 0)
       {
          g_lastFilterReason = "No TP (pending)";
          Print("[PENDING] No TP - skipping");
          return;
       }
       if(EnableTimeFilter)
       {
          MqlDateTime dt; TimeCurrent(dt);
          int curHour = dt.hour;
          bool inWindow = false;
          if(TimeFilterStartHour <= TimeFilterEndHour)
             inWindow = (curHour >= TimeFilterStartHour && curHour <= TimeFilterEndHour);
          else
             inWindow = (curHour >= TimeFilterStartHour || curHour <= TimeFilterEndHour);
          if(!inWindow)
          {
             g_lastFilterReason = "Outside time filter";
             Print("[PENDING] Time filter: hour=", curHour, " outside ", TimeFilterStartHour, "-", TimeFilterEndHour);
             return;
          }
       }
       int spreadP = (int)SymbolInfoInteger(pSym, SYMBOL_SPREAD);
       int effectivePendingMaxSpread = TCU_EffectiveMaxSpreadPoints();
       if(TCU_EffectiveSpreadFilterEnabled() && spreadP > effectivePendingMaxSpread)
       {
          g_lastFilterReason = "Spread: " + IntegerToString(spreadP);
          Print("[PENDING] Spread too high! ", spreadP, " > ", effectivePendingMaxSpread);
          return;
       }
       
      // Build list of (TP, lots) pairs to place
      double tpArr[3];  double lotsArr[3];  int legCount = 0;
      double minLot  = SymbolInfoDouble(pSym, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(pSym, SYMBOL_VOLUME_STEP);
      
      if(EnablePendingMultiTP && (pTP2 > 0 || pTP3 > 0))
      {
         // Multi-TP: split lots by distribution
         if(minLot <= 0) minLot = 0.01;
         if(lotStep <= 0) lotStep = minLot;
         int numTPs = 1 + (pTP2 > 0 ? 1 : 0) + (pTP3 > 0 ? 1 : 0);
         if(numTPs > MaxTPTargets) numTPs = MaxTPTargets;

         double legs[3]; legs[0] = 0; legs[1] = 0; legs[2] = 0;
         if(!TCU_BuildSignalTpLots(pSym, lotsTotal, numTPs, legs[0], legs[1], legs[2], "PENDING"))
         {
            g_lastFilterReason = "SigTP lots invalid";
            return;
         }
         double l1 = legs[0];
         double l2 = (pTP2 > 0 && numTPs >= 2) ? legs[1] : 0;
         double l3 = (pTP3 > 0 && numTPs >= 3) ? legs[2] : 0;
         tpArr[0] = pTP;  lotsArr[0] = l1;  legCount = 1;
         if(pTP2 > 0 && legCount < numTPs) { tpArr[legCount] = pTP2; lotsArr[legCount] = l2; legCount++; }
         if(pTP3 > 0 && legCount < numTPs) { tpArr[legCount] = pTP3; lotsArr[legCount] = l3; legCount++; }
      }
      else
      {
         // Single TP
         tpArr[0] = pTP; lotsArr[0] = lotsTotal; legCount = 1;
      }

      int effectivePendingMaxOpen = TCU_EffectiveMaxOpenPositions();
      int pendingActiveCount = PositionsTotal() + OrdersTotal();
      if(effectivePendingMaxOpen > 0 && pendingActiveCount + legCount > effectivePendingMaxOpen)
      {
         g_lastFilterReason = "Max positions (pending)";
         Print("[PENDING] Max open positions would be exceeded (positions=", PositionsTotal(),
               " pendings=", OrdersTotal(), " planned=", legCount, " cap=", effectivePendingMaxOpen, "). Skipping.");
         return;
      }
      
      g_trade.SetExpertMagicNumber(MagicNumber);
      int placed = 0;
      for(int leg = 0; leg < legCount; leg++)
      {
         if(!ArmExecution)
         {
            g_lastFilterReason = "DISARMED";
            Print("[PENDING] Placement aborted mid-flight -- EA was DISARMED before leg ", leg+1);
            break;
         }
         double legTP   = tpArr[leg];
         double legLots = lotsArr[leg];
         double openerStopLimit = (pendingType == "BUY_STOP_LIMIT" || pendingType == "SELL_STOP_LIMIT") ? pStopLimit : 0;
         if(legLots <= 0) legLots = minLot;
         Print("[PENDING] Leg ", leg+1, "/", legCount, " | ", pendingType, " ", pSym, " @ ", pEntry, " SL:", pSL, " TP:", legTP, " Lots:", legLots);
         if(g_trade.OrderOpen(pSym, orderType, legLots, openerStopLimit, pEntry, pSL, legTP, ORDER_TIME_GTC, 0, TCU_TradeComment("TCU_pending")))
         {
            ulong pendTicket = g_trade.ResultOrder();
            Print("[PENDING] Leg ", leg+1, " placed: ticket #", pendTicket);
            WriteReport("PENDING", pSym, pDir, legLots, 0, pendTicket, pendingType);
            if(EnablePendingExpiry)
            {
               int sz = ArraySize(g_pendingExpTickets);
               ArrayResize(g_pendingExpTickets, sz + 1);
               ArrayResize(g_pendingExpTimes, sz + 1);
               g_pendingExpTickets[sz] = pendTicket;
               g_pendingExpTimes[sz]   = TimeCurrent();
            }
            placed++;
         }
         else
         {
            Print("[PENDING] Leg ", leg+1, " failed: ", g_trade.ResultComment());
            g_lastError = "Pending failed: " + g_trade.ResultComment();
         }
      }
      if(placed > 0)
      {
         DoAlert("Pending " + pendingType + " " + pSym + " x" + IntegerToString(placed) + " legs @ " + DoubleToString(pEntry, digits));
         // [v6.00 FIX 2026-04-26][R2] Pending-order placement succeeded -- persist dedup hash now.
         if(g_currentSignalHash != 0) { MarkProcessed(g_currentSignalHash); g_currentSignalHash = 0; }
      }
      return;
   }
   
   // Word-boundary detection: prevents BUYING/SELLING/BUYOUT/SHORTING from triggering
   bool isBuy = (WordFind(uMsg, "BUY") >= 0 || WordFind(uMsg, "LONG") >= 0);
   bool isSell = (WordFind(uMsg, "SELL") >= 0 || WordFind(uMsg, "SHORT") >= 0);
   
   if(!isBuy && !isSell)
   {
      g_lastFilterReason = "No BUY/SELL direction";
      DiagLog("BLOCKED", "No BUY/SELL/LONG/SHORT keyword found");
      DiagSep();
      return;
   }
   
   // Additional filter: direction keyword should appear in first 120 chars
   // Real signals have direction near the top, not buried in a paragraph
   int buyPos = StringFind(uMsg, isBuy ? "BUY" : "SELL");
   if(buyPos < 0) buyPos = StringFind(uMsg, isBuy ? "LONG" : "SHORT");
   if(buyPos > 120)
   {
      g_lastFilterReason = "Direction buried > 120 chars";
      DiagLog("BLOCKED", "Direction keyword at pos " + IntegerToString(buyPos) + " (>120). Message looks like news/chat, not a signal");
      Print("[FILTER] Direction keyword too far into message (pos ", buyPos, "), skipping");
      return;
   }
   
   // Dedup: hash the signal to prevent re-execution across ALL sources
   // Use only message content (not src) so BotAPI + Bridge don't both fire
   ulong hash = CalcHash(uMsg);
   if(EnableDuplicateFilter && IsProcessed(hash))
   {
      g_lastFilterReason = "Duplicate signal";
      DiagLog("BLOCKED", "Duplicate -- hash already processed. Turn off EnableDuplicateFilter to bypass");
      DiagSep();
      Print("[TCU] Duplicate signal ignored (already processed)");
      return;
   }
   // [v6.00 FIX 2026-04-26][R2] Stash the hash; do NOT persist it yet.
   // MarkProcessed(g_currentSignalHash) is called only at successful exit points (executed
   // trade, executed command). Signals rejected by transient filters (news, spread, margin,
   // prop SL missing) leave the hash unmarked so re-sending the same text after the filter
   // clears will re-process correctly.
   g_currentSignalHash = hash;
   
   string sym = ExtractSym(uMsg);
   if(StringLen(sym) == 0)
   {
      g_lastFilterReason = "No symbol found";
      DiagLog("BLOCKED", "No symbol extracted from: \"" + StringSubstr(msg,0,60) + "\"");
      DiagSep();
      Print("[FILTER] No valid symbol found in message, skipping: ", StringSubstr(msg, 0, 60));
      return;
   }
   sym = MapSym(sym);
   
   double sl = 0;
   double tp = 0;
   if(CopySL)
   {
      sl = ExtractNum(uMsg, "SL");
      if(sl == 0) sl = ExtractNum(uMsg, "STOPLOSS");
      if(sl == 0) sl = ExtractNum(uMsg, "STOP LOSS");
      if(sl == 0) sl = ExtractNum(uMsg, "S/L");
      if(sl == 0) sl = ExtractNum(uMsg, "S.L.");
      if(sl == 0) sl = ExtractNum(uMsg, "RISK AT");
      if(sl == 0) sl = ExtractNum(uMsg, "RISKAT");
      if(sl == 0) sl = ExtractNum(uMsg, "INVALIDATION");
      if(sl == 0) sl = ExtractNum(uMsg, "PROTECTION");
      if(sl == 0) sl = ExtractNum(uMsg, "STP");
      if(sl == 0 && EnableCustomSLTPKeywords) sl = ExtractNumCustom(uMsg, CustomSLKeywords);
      if(sl > 0 && TCU_MessageUsesRelativeSL(uMsg))
      {
         g_lastFilterReason = "Relative SL not supported";
         DiagLog("FILTERED","Relative SL wording detected (pips/points) -- ignoring SL");
         DiagSep();
         Print("[FILTER] Signal uses relative SL wording (pips/points). Relative SL/TP mode is not supported here, so SL will be ignored.");
         g_lastError = "Relative SL wording not supported";
         sl = 0;
      }
   }
   if(CopyTP && EnableSignalTP)
   {
      // Try TP1 first (multi-TP), fallback to TP
      tp = ExtractNum(uMsg, "TP1");
      if(tp == 0) tp = ExtractNum(uMsg, "T1");
      if(tp == 0) tp = ExtractNum(uMsg, "TP");
      if(tp == 0) tp = ExtractNum(uMsg, "TAKEPROFIT");
      if(tp == 0) tp = ExtractNum(uMsg, "TAKE PROFIT");
      if(tp == 0) tp = ExtractNum(uMsg, "T/P");
      if(tp == 0) tp = ExtractNum(uMsg, "TARGET");
      if(tp == 0) tp = ExtractNum(uMsg, "PT");
      if(tp == 0) tp = ExtractNum(uMsg, "EXIT");
      if(tp == 0) tp = ExtractNum(uMsg, "GOAL");
      if(tp == 0) tp = ExtractNum(uMsg, "PROFIT TARGET");
      if(tp == 0 && EnableCustomSLTPKeywords) tp = ExtractNumCustom(uMsg, CustomTPKeywords);
      
      // Log extra signal TPs if present
      double debugTP2 = ExtractNum(uMsg, "TP2");
      double debugTP3 = ExtractNum(uMsg, "TP3");
      if(debugTP2 > 0 || debugTP3 > 0)
      {
         int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         string multiTPMsg = "Multi-TP detected: TP1=" + DoubleToString(tp, (digits > 0 ? digits : 2));
         if(debugTP2 > 0) multiTPMsg += ", TP2=" + DoubleToString(debugTP2, (digits > 0 ? digits : 2));
         if(debugTP3 > 0) multiTPMsg += ", TP3=" + DoubleToString(debugTP3, (digits > 0 ? digits : 2));
         Print("[SIGNAL] ", multiTPMsg);
      }
   }
   bool marketRelativeTP = TCU_MessageUsesRelativeTP(uMsg);
   if(marketRelativeTP && tp > 0)
   {
      g_lastFilterReason = "Relative TP ignored";
      DiagLog("FILTERED","Relative TP wording detected before armour -- ignoring TP1");
      Print("[FILTER] Relative TP wording detected before armour. TP1 ignored.");
      g_lastError = "Relative TP wording not supported";
      tp = 0;
   }
   
   string dir = "BUY";
   if(isSell) dir = "SELL";
   
   // ARMOUR RULE: Require direction + symbol + at least one price level
   // Prevents random chat text from ever opening trades
   if(RequireEntryArmour)
   {
      // Check for entry price too (@ 2630, ENTRY 1.0845, etc.)
      double entryPrice = ExtractNum(uMsg, "ENTRY");
      if(entryPrice == 0) entryPrice = ExtractNum(uMsg, "@");
      if(entryPrice == 0) entryPrice = ExtractNum(uMsg, "PRICE");
      
      // Detect entry range pattern: number-number (e.g. 2030-2034, 1.0845-1.0860)
      // This counts as "has entry" even though we don't use the range for placement
      bool hasEntryRange = false;
      for(int ri = 0; ri < StringLen(uMsg) - 2; ri++)
      {
         ushort ch = StringGetCharacter(uMsg, ri);
         if(ch == '-' && ri > 0 && ri < StringLen(uMsg) - 1)
         {
            ushort before = StringGetCharacter(uMsg, ri - 1);
            ushort after = StringGetCharacter(uMsg, ri + 1);
            if((before >= '0' && before <= '9') && (after >= '0' && after <= '9'))
            {
               hasEntryRange = true;
               break;
            }
         }
      }
      
      bool hasAnyPrice = (sl > 0 || tp > 0 || entryPrice > 0 || hasEntryRange);
      if(!hasAnyPrice)
      {
         g_lastFilterReason = "Armour: no SL/TP/entry"; DiagLog("FILTERED","ARMOUR: signal lacks SL/TP/entry (RequireEntryArmour=true)"); DiagSep();
         Print("[ARMOUR] Signal has direction + symbol but NO SL/TP/entry price. Skipping: ", StringSubstr(msg, 0, 80));
         g_lastError = "Armour: no SL/TP/entry found";
         return;
      }
   }
   
   // Extract TP2/TP3 for signal multi-TP mode
   double tp2 = 0, tp3 = 0;
   if(EnableMultiTP && !EnableMartingale && EnableSignalTP)
   {
      tp2 = ExtractNum(uMsg, "TP2");
      if(tp2 == 0) tp2 = ExtractNum(uMsg, "T2");
      if(tp2 == 0) tp2 = ExtractNum(uMsg, "TARGET 2");
      if(tp2 == 0) tp2 = ExtractNum(uMsg, "TAKE PROFIT 2");
      if(tp2 == 0) tp2 = ExtractNum(uMsg, "PT2");
      tp3 = ExtractNum(uMsg, "TP3");
      if(tp3 == 0) tp3 = ExtractNum(uMsg, "T3");
      if(tp3 == 0) tp3 = ExtractNum(uMsg, "TARGET 3");
      if(tp3 == 0) tp3 = ExtractNum(uMsg, "TAKE PROFIT 3");
      if(tp3 == 0) tp3 = ExtractNum(uMsg, "PT3");
      // SEQUENTIAL TP FIX: If extra TPs are still missing, scan for multiple lines of bare "TP <price>"
      // Channels that send "TP 5169\nTP 5175\nTP 5200" have no numbers on TP keyword.
      // We collect all bare TP values and assign 1st=tp, 2nd=tp2, 3rd=tp3.
      if(tp2 == 0 || tp3 == 0)
      {
         double tpList[10]; int tpCount = 0;
         int searchPos = 0;
         int msgLen = StringLen(uMsg);
         while(searchPos < msgLen - 2 && tpCount < 10)
         {
            int tpPos = StringFind(uMsg, "TP", searchPos);
            if(tpPos < 0) break;
            // Make sure "TP" is NOT followed by a digit (that would be TP1, TP2, TP3, handled above)
            ushort nextCh = (tpPos + 2 < msgLen) ? StringGetCharacter(uMsg, tpPos + 2) : 0;
            bool nextIsDigit = (nextCh >= '0' && nextCh <= '9');
            // Make sure "TP" is at word boundary (not TAKEPROFIT, STOP etc.)
            ushort prevCh = (tpPos > 0) ? StringGetCharacter(uMsg, tpPos - 1) : ' ';
            bool prevIsLetter = ((prevCh >= 'A' && prevCh <= 'Z') || (prevCh >= 'a' && prevCh <= 'z'));
            if(!nextIsDigit && !prevIsLetter)
            {
               // Find the number after this bare "TP"
               int numStart = tpPos + 2;
               while(numStart < msgLen)
               {
                  ushort sc = StringGetCharacter(uMsg, numStart);
                  if(sc == ' ' || sc == ':' || sc == '=') numStart++;
                  else break;
               }
               if(numStart < msgLen)
               {
                  string numBuf2 = "";
                  int ni = numStart;
                  while(ni < msgLen)
                  {
                     ushort nc = StringGetCharacter(uMsg, ni);
                     if((nc >= '0' && nc <= '9') || nc == '.') { numBuf2 += ShortToString(nc); ni++; }
                     else break;
                  }
                  double tpVal = StringToDouble(numBuf2);
                  if(tpVal > 0.001)
                  {
                     tpList[tpCount++] = tpVal;
                  }
               }
            }
            searchPos = tpPos + 2;
         }
         // Assign sequential: tpList[0]=tp1, tpList[1]=tp2, tpList[2]=tp3
         if(tpCount >= 1 && tp == 0)  tp  = tpList[0];
         if(tpCount >= 2 && tp2 == 0) tp2 = tpList[1];
         if(tpCount >= 3 && tp3 == 0) tp3 = tpList[2];
         if(tpCount > 1) Print("[SIGNAL] Sequential TP scan: found ", tpCount, " bare TP values. tp=", tp, " tp2=", tp2, " tp3=", tp3);
      }
   }
   if((tp > 0 || tp2 > 0 || tp3 > 0) && TCU_MessageUsesRelativeTP(uMsg))
   {
      g_lastFilterReason = "Relative TP not supported";
      DiagLog("FILTERED","Relative TP wording detected (pips/points) -- ignoring all signal TPs");
      DiagSep();
      Print("[FILTER] Signal uses relative TP wording (pips/points). Relative SL/TP mode is not supported here, so all signal TPs will be ignored.");
      g_lastError = "Relative TP wording not supported";
      tp = 0; tp2 = 0; tp3 = 0;
   }
   ExecSignal(dir, sym, sl, tp, src, tp2, tp3, signalLots);
}

//+------------------------------------------------------------------+
string ExtractSym(string msg)
{
   // 0. Normalize slash-separated pairs: USD/JPY => USDJPY, EUR/GBP => EURGBP
   string normMsg = "";
   int msgLen0 = StringLen(msg);
   int si = 0;
   while(si < msgLen0)
   {
      if(si + 6 < msgLen0 && StringGetCharacter(msg, si + 3) == '/')
      {
         // Check if chars before and after slash are all uppercase letters
         bool validPair = true;
         for(int ci2 = 0; ci2 < 3; ci2++)
         {
            ushort b = StringGetCharacter(msg, si + ci2);
            ushort a = StringGetCharacter(msg, si + 4 + ci2);
            if(b < 'A' || b > 'Z' || a < 'A' || a > 'Z') { validPair = false; break; }
         }
         if(validPair)
         {
            normMsg += StringSubstr(msg, si, 3) + StringSubstr(msg, si + 4, 3);
            si += 7;
            continue;
         }
      }
      normMsg += StringSubstr(msg, si, 1);
      si++;
   }
   msg = normMsg;
   
   // 1. Check user-defined aliases first (WordFind for short aliases to prevent GOLD=>GOLDEN)
   for(int i = 0; i < g_aliasCount; i++)
   {
      bool aliasFound = false;
      if(StringLen(g_aliasNames[i]) <= 6)
         aliasFound = (WordFind(msg, g_aliasNames[i]) >= 0);  // Whole word match for short aliases
      else
         aliasFound = (StringFind(msg, g_aliasNames[i]) >= 0); // Substring ok for long aliases
      if(aliasFound)
         return g_aliasSymbols[i];
   }
   
   // 2. Common hardcoded symbols and aliases
   // Use WordFind for short aliases to prevent GOLDEN/SILVERWARE matching
   if(StringFind(msg, "XAUUSD") >= 0) return "XAUUSD";
   if(WordFind(msg, "GOLD") >= 0)    return "XAUUSD";
   if(StringFind(msg, "XAGUSD") >= 0) return "XAGUSD";
   if(WordFind(msg, "SILVER") >= 0)  return "XAGUSD";
   if(StringFind(msg, "EURUSD") >= 0) return "EURUSD";
   if(WordFind(msg, "FIBER") >= 0)   return "EURUSD";
   if(StringFind(msg, "GBPUSD") >= 0) return "GBPUSD";
   if(WordFind(msg, "CABLE") >= 0)   return "GBPUSD";
   if(StringFind(msg, "USDJPY") >= 0) return "USDJPY";
   if(WordFind(msg, "GOPHER") >= 0)  return "USDJPY";
   if(StringFind(msg, "AUDUSD") >= 0) return "AUDUSD";
   if(WordFind(msg, "AUSSIE") >= 0)  return "AUDUSD";
   if(StringFind(msg, "NZDUSD") >= 0) return "NZDUSD";
   if(WordFind(msg, "KIWI") >= 0)    return "NZDUSD";
   if(StringFind(msg, "USDCAD") >= 0) return "USDCAD";
   if(WordFind(msg, "LOONIE") >= 0)  return "USDCAD";
   if(StringFind(msg, "USDCHF") >= 0) return "USDCHF";
   if(WordFind(msg, "SWISSIE") >= 0) return "USDCHF";
   if(StringFind(msg, "BTCUSD") >= 0) return "BTCUSD";
   if(WordFind(msg, "BITCOIN") >= 0)  return "BTCUSD";
   if(StringFind(msg, "ETHUSD") >= 0) return "ETHUSD";
   if(WordFind(msg, "ETHEREUM") >= 0) return "ETHUSD";
   if(WordFind(msg, "US30") >= 0)    return "US30";
   if(WordFind(msg, "DOW") >= 0)     return "US30";
   if(StringFind(msg, "NAS100") >= 0) return "NAS100";
   if(StringFind(msg, "SPX500") >= 0) return "SPX500";
   if(WordFind(msg, "USTEC") >= 0)   return "USTEC";
   if(WordFind(msg, "DJ30") >= 0)    return "DJ30";
   if(WordFind(msg, "NAS") >= 0)     return "NAS100";
   if(WordFind(msg, "DAX") >= 0)     return "GER40";
   if(WordFind(msg, "GER40") >= 0)   return "GER40";
   if(WordFind(msg, "UK100") >= 0)   return "UK100";
   if(StringFind(msg, "GBPJPY") >= 0) return "GBPJPY";
   if(StringFind(msg, "EURJPY") >= 0) return "EURJPY";
   if(StringFind(msg, "EURGBP") >= 0) return "EURGBP";
   if(StringFind(msg, "AUDCAD") >= 0) return "AUDCAD";
   if(StringFind(msg, "AUDNZD") >= 0) return "AUDNZD";
   if(StringFind(msg, "NZDJPY") >= 0) return "NZDJPY";
   if(StringFind(msg, "CADJPY") >= 0) return "CADJPY";
   if(StringFind(msg, "CHFJPY") >= 0) return "CHFJPY";
   if(StringFind(msg, "EURAUD") >= 0) return "EURAUD";
   if(StringFind(msg, "EURNZD") >= 0) return "EURNZD";
   if(StringFind(msg, "EURCAD") >= 0) return "EURCAD";
   if(StringFind(msg, "EURCHF") >= 0) return "EURCHF";
   if(StringFind(msg, "GBPAUD") >= 0) return "GBPAUD";
   if(StringFind(msg, "GBPNZD") >= 0) return "GBPNZD";
   if(StringFind(msg, "GBPCAD") >= 0) return "GBPCAD";
   if(StringFind(msg, "GBPCHF") >= 0) return "GBPCHF";
   if(StringFind(msg, "AUDCHF") >= 0) return "AUDCHF";
   if(StringFind(msg, "AUDJPY") >= 0) return "AUDJPY";
   if(StringFind(msg, "CADCHF") >= 0) return "CADCHF";
   if(StringFind(msg, "NZDCAD") >= 0) return "NZDCAD";
   if(StringFind(msg, "NZDCHF") >= 0) return "NZDCHF";
   
   // 3. Dynamic fallback: extract the word right after BUY/SELL/LONG/SHORT
   //    and check if it's a valid broker symbol (with optional suffix)
   string keywords[] = {"BUY ", "SELL ", "LONG ", "SHORT "};
   for(int k = 0; k < 4; k++)
   {
      int kPos = StringFind(msg, keywords[k]);
      if(kPos < 0) continue;
      
      int wStart = kPos + StringLen(keywords[k]);
      // Skip spaces
      while(wStart < StringLen(msg) && StringGetCharacter(msg, wStart) == ' ') wStart++;
      
      // Extract the next word (letters and digits only)
      string word = "";
      for(int j = wStart; j < StringLen(msg); j++)
      {
         ushort c = StringGetCharacter(msg, j);
         if((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
            word += ShortToString(c);
         else
            break;
      }
      
      if(StringLen(word) < 3) continue;
      
      // Check if it's a valid symbol (with and without suffix)
      if(SymbolInfoDouble(word, SYMBOL_BID) > 0) return word;
      if(StringLen(SymbolSuffix) > 0 && SymbolInfoDouble(word + SymbolSuffix, SYMBOL_BID) > 0) return word;
      // [v6.x FIX 2026-06-12] Auto-suffix and full suffix mutation so exotic pairs
      // (EURNOK, USDSEK, USDTRY, etc.) are found even with broker suffixes like 'm', '.raw'
      if(StringLen(g_autoSuffix) > 0 && SymbolExists(word + g_autoSuffix)) return word;
      if(TrySuffixMutation(word) != "") return word;
   }
   
   return "";
}

//+------------------------------------------------------------------+
bool TCU_KeywordUsesRelativeDistance(string msg, string kw)
{
   int searchStart = 0;
   int len = StringLen(msg);
   int kwLen = StringLen(kw);

   while(searchStart < len)
   {
      int pos = StringFind(msg, kw, searchStart);
      if(pos < 0) return false;

      int afterKw = pos + kwLen;
      if(afterKw < len)
      {
         ushort nextChar = StringGetCharacter(msg, afterKw);
         if(nextChar >= '0' && nextChar <= '9')
         {
            searchStart = afterKw;
            continue;
         }
      }

      int scanEnd = MathMin(len, afterKw + 32);
      string tail = StringSubstr(msg, afterKw, scanEnd - afterKw);
      if(StringFind(tail, "PIP") >= 0 || StringFind(tail, "POINT") >= 0)
         return true;

      searchStart = afterKw;
   }

   return false;
}

//+------------------------------------------------------------------+
bool TCU_MessageUsesRelativeSL(string msg)
{
   return TCU_KeywordUsesRelativeDistance(msg, "SL")
       || TCU_KeywordUsesRelativeDistance(msg, "STOPLOSS")
       || TCU_KeywordUsesRelativeDistance(msg, "STOP LOSS")
       || TCU_KeywordUsesRelativeDistance(msg, "S/L")
       || TCU_KeywordUsesRelativeDistance(msg, "S.L.")
       || TCU_KeywordUsesRelativeDistance(msg, "RISK AT")
       || TCU_KeywordUsesRelativeDistance(msg, "RISKAT")
       || TCU_KeywordUsesRelativeDistance(msg, "INVALIDATION")
       || TCU_KeywordUsesRelativeDistance(msg, "PROTECTION")
       || TCU_KeywordUsesRelativeDistance(msg, "STP");
}

//+------------------------------------------------------------------+
bool TCU_MessageUsesRelativeTP(string msg)
{
   return TCU_KeywordUsesRelativeDistance(msg, "TP1")
       || TCU_KeywordUsesRelativeDistance(msg, "T1")
       || TCU_KeywordUsesRelativeDistance(msg, "TP")
       || TCU_KeywordUsesRelativeDistance(msg, "TAKEPROFIT")
       || TCU_KeywordUsesRelativeDistance(msg, "TAKE PROFIT")
       || TCU_KeywordUsesRelativeDistance(msg, "T/P")
       || TCU_KeywordUsesRelativeDistance(msg, "TARGET")
       || TCU_KeywordUsesRelativeDistance(msg, "PT")
       || TCU_KeywordUsesRelativeDistance(msg, "EXIT")
       || TCU_KeywordUsesRelativeDistance(msg, "GOAL")
       || TCU_KeywordUsesRelativeDistance(msg, "PROFIT TARGET");
}

//+------------------------------------------------------------------+
// Parse "TICKETS:t1,t2,t3" from a message into an array of ulongs.
// Returns the count found (0 = no TICKETS: tag → no ticket filtering).
int ExtractTickets(string msg, ulong &out[])
{
   ArrayResize(out, 0);
   int pos = StringFind(msg, "TICKETS:");
   if(pos < 0) return 0;
   // TICKETS:NONE means all positions for this signal are already closed — skip entirely.
   if(StringFind(msg, "TICKETS:NONE") >= 0) return -1;
   string tail = StringSubstr(msg, pos + 8);
   // Trim at first whitespace
   int end = StringLen(tail);
   for(int i = 0; i < StringLen(tail); i++)
   {
      ushort c = StringGetCharacter(tail, i);
      if(c == ' ' || c == '\t' || c == '\n' || c == '\r') { end = i; break; }
   }
   tail = StringSubstr(tail, 0, end);
   string parts[];
   int n = StringSplit(tail, ',', parts);
   ArrayResize(out, n);
   int found = 0;
   for(int i = 0; i < n; i++)
   {
      StringTrimLeft(parts[i]); StringTrimRight(parts[i]);
      ulong t = (ulong)StringToInteger(parts[i]);
      if(t > 0) { out[found] = t; found++; }
   }
   ArrayResize(out, found);
   return found;
}

bool TicketInList(ulong ticket, ulong &list[], int count)
{
   if(count == 0)  return true;  // no TICKETS: tag → no filter, match all
   if(count <  0)  return false; // TICKETS:NONE → all closed, reject all
   for(int i = 0; i < count; i++)
      if(list[i] == ticket) return true;
   return false;
}

//+------------------------------------------------------------------+
double ExtractNum(string msg, string kw)
{
   int searchStart = 0;
   int len = StringLen(msg);
   
   while(searchStart < len)
   {
      int pos = StringFind(msg, kw, searchStart);
      if(pos < 0) return 0;
      
      int afterKw = pos + StringLen(kw);
      
      // Word boundary check: if digit immediately follows keyword,
      // it's part of a longer keyword (e.g. "TP" found in "TP1"). Skip.
      if(afterKw < len)
      {
         ushort nextChar = StringGetCharacter(msg, afterKw);
         if(nextChar >= '0' && nextChar <= '9')
         {
            searchStart = afterKw;
            continue; // Find next occurrence
         }
      }
      
      // Skip non-digit characters after keyword (spaces, colons, equals, etc.)
      pos = afterKw;
      while(pos < len)
      {
         ushort c = StringGetCharacter(msg, pos);
         if((c >= 48 && c <= 57) || c == 46) break;
         pos++;
      }
      
      string numStr = "";
      while(pos < len)
      {
         ushort c = StringGetCharacter(msg, pos);
         if((c >= 48 && c <= 57) || c == 46)
            numStr += ShortToString(c);
         else if(c == 44) { pos++; continue; } // skip commas in prices like 67,500
         else
            break;
         pos++;
      }
      
      if(StringLen(numStr) > 0)
         return StringToDouble(numStr);
      
      searchStart = pos;
   }
   
   return 0;
}

double ExtractNumLast(string msg, string kw)
{
   double last = 0;
   int searchStart = 0;
   int len = StringLen(msg);

   while(searchStart < len)
   {
      int pos = StringFind(msg, kw, searchStart);
      if(pos < 0) break;

      int afterKw = pos + StringLen(kw);
      if(afterKw < len)
      {
         ushort nextChar = StringGetCharacter(msg, afterKw);
         if(nextChar >= '0' && nextChar <= '9')
         {
            searchStart = afterKw;
            continue;
         }
      }

      pos = afterKw;
      while(pos < len)
      {
         ushort c = StringGetCharacter(msg, pos);
         if((c >= 48 && c <= 57) || c == 46) break;
         pos++;
      }

      string numStr = "";
      while(pos < len)
      {
         ushort c = StringGetCharacter(msg, pos);
         if((c >= 48 && c <= 57) || c == 46)
            numStr += ShortToString(c);
         else if(c == 44) { pos++; continue; }
         else
            break;
         pos++;
      }

      if(StringLen(numStr) > 0)
         last = StringToDouble(numStr);

      searchStart = afterKw;
   }

   return last;
}

//+------------------------------------------------------------------+
// CUSTOM KEYWORD EXTRACTION: Try user-defined keywords (comma-separated)
//+------------------------------------------------------------------+
double ExtractNumCustom(string msg, string keywords)
{
   if(StringLen(keywords) == 0) return 0;
   
   string items[];
   int count = StringSplit(keywords, ',', items);
   
   for(int i = 0; i < count; i++)
   {
      StringTrimLeft(items[i]);
      StringTrimRight(items[i]);
      StringToUpper(items[i]);
      if(StringLen(items[i]) == 0) continue;
      
      double val = ExtractNum(msg, items[i]);
      if(val > 0)
      {
         Print("[CUSTOM_KW] Matched keyword '", items[i], "' -> value: ", val);
         return val;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Modify existing positions with new SL/TP during cooldown          |
//+------------------------------------------------------------------+
bool ModifyExistingPositions(string sym, string dir, double sl, double tp, string src)
{
   int modifiedCount = 0;
   int totalPositions = 0;
   
   // Get symbol info for normalization
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minStop = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   
   // Normalize SL/TP to correct digits
   double normSL = (sl > 0 && CopySL) ? NormalizeDouble(sl, digits) : 0;
   double normTP = (tp > 0 && CopyTP) ? NormalizeDouble(tp, digits) : 0;
   
   // FIX: Find the MOST RECENTLY opened matching position (latest open time).
   // Only modify that one -- not all positions for this symbol+direction.
   ulong latestTicket = 0;
   datetime latestTime = 0;
   for(int s = PositionsTotal() - 1; s >= 0; s--)
   {
      if(PositionGetTicket(s) <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      string posDir2 = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(posDir2 != dir) continue;
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(openTime >= latestTime)
      {
         latestTime = openTime;
         latestTicket = PositionGetTicket(s);
      }
   }
   if(latestTicket == 0)
   {
      Print("[MODIFY] No matching ", dir, " position found for ", sym);
      return false;
   }
   Print("[MODIFY] Targeting most recent ", dir, " ", sym, " ticket #", latestTicket);
   
   // Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) > 0)
      {
         // Only process the specific most-recent ticket we identified above
         if(PositionGetTicket(i) != latestTicket) continue;
         if(PositionGetString(POSITION_SYMBOL) == sym && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            totalPositions++;
            
            // Check direction match
            string posDir = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";
            
            if(posDir == dir)
            {
               double currentSL = PositionGetDouble(POSITION_SL);
               double currentTP = PositionGetDouble(POSITION_TP);
               double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               
               // Check if we need to modify
               bool needModify = false;
               
               // Check SL modification
               if(normSL > 0)
               {
                  if(currentSL != normSL)
                  {
                     // Validate SL distance from open price
                     double slDistance = MathAbs(openPrice - normSL);
                     if(slDistance >= minStop)
                     {
                        needModify = true;
                     }
                     else
                     {
                        Print("[MODIFY] SL distance too small: ", DoubleToString(slDistance, digits),
                              " < min: ", DoubleToString(minStop, digits));
                     }
                  }
               }
               
               // Check TP modification
               if(normTP > 0)
               {
                  if(currentTP != normTP)
                  {
                     // Validate TP distance from open price
                     double tpDistance = MathAbs(normTP - openPrice);
                     if(tpDistance >= minStop)
                     {
                        needModify = true;
                     }
                     else
                     {
                        Print("[MODIFY] TP distance too small: ", DoubleToString(tpDistance, digits),
                              " < min: ", DoubleToString(minStop, digits));
                     }
                  }
               }
               
               // Perform modification if needed
               if(needModify)
               {
                  // Use existing SL/TP if not provided
                  double newSL = (normSL > 0) ? normSL : currentSL;
                  double newTP = (normTP > 0) ? normTP : currentTP;
                  
                  Print("[MODIFY] Attempting to modify position ", PositionGetTicket(i), 
                        " SL:", currentSL, "->", newSL, " TP:", currentTP, "->", newTP);
                  
                  if(g_trade.PositionModify(PositionGetTicket(i), newSL, newTP))
                  {
                     modifiedCount++;
                     Print("[MODIFY] Successfully modified position ", PositionGetTicket(i));
                     WriteReport("MODIFY_SLTP", sym, dir, PositionGetDouble(POSITION_VOLUME), PositionGetTicket(i), 0,
                                 "SL=" + DoubleToString(newSL, digits) + " TP=" + DoubleToString(newTP, digits) + " src=" + src);
                     
                     // Send notification if enabled
                     if(EnableTelegramSend)
                     {
                        string msg = TelegramSendTag + " Modified " + dir + " " + sym + 
                                    " SL:" + DoubleToString(newSL, digits) + 
                                    " TP:" + DoubleToString(newTP, digits) + 
                                    " " + TelegramSendSuffix;
                        ArrayResize(g_tgQueue, g_tgQueueSize + 1);
                        ArrayResize(g_tgQueueRetries, g_tgQueueSize + 1);
                        g_tgQueue[g_tgQueueSize] = msg;
                        g_tgQueueRetries[g_tgQueueSize] = 0;
                        g_tgQueueSize++;
                     }
                  }
                  else
                  {
                     Print("[MODIFY] Failed to modify position ", PositionGetTicket(i), 
                           " Error: ", g_trade.ResultComment());
                  }
               }
            }
         }
      }
   }
   
   Print("[MODIFY] Modified ", modifiedCount, " out of ", totalPositions, 
         " positions for ", dir, " ", sym);
   
   return (modifiedCount > 0);
}

//+------------------------------------------------------------------+
void SendBridgeCallback(string signalRef, string ticket, string action, string symbol, double sl=0, double tp=0)
{
   if(!EnableBridgeMode) return;
   // CLOSED callbacks have no signalRef (bridge looks up by ticket); all others require one.
   if(action != "CLOSED" && StringLen(signalRef) == 0) return;
   string url = "http://127.0.0.1:" + IntegerToString(BridgePort) + "/callback";
   string clientId = AccountInfoString(ACCOUNT_COMPANY) + "|" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN));
   string body = "{\"signal_ref\":\"" + signalRef + "\""
               + ",\"ticket\":" + ticket
               + ",\"action\":\"" + action + "\""
               + ",\"symbol\":\"" + symbol + "\""
               + ",\"client_id\":\"" + clientId + "\""
               + (sl > 0 ? ",\"sl\":" + DoubleToString(sl, 5) : "")
               + (tp > 0 ? ",\"tp\":" + DoubleToString(tp, 5) : "")
               + "}";
   uchar post[], result[];
   StringToCharArray(body, post, 0, StringLen(body), CP_UTF8);
   string headers = "Content-Type: application/json\r\nX-NTS-Auth: " + NTS_AuthToken() + "\r\n";
   string respHeaders;
   int res = WebRequest("POST", url, headers, 2000, post, result, respHeaders);
   if(res == 200 || res == 201)
      Print("[Bridge] Callback sent: ", action, " #", ticket, " ref=", signalRef);
   else if(res == -1)
      Print("[Bridge] Callback blocked -- add http://127.0.0.1 to MT5 WebRequest URLs");
   else
      Print("[Bridge] Callback HTTP=", res, " action=", action);
   // Buffer OPENED trades for heartbeat backup path (prop-mode reliability)
   if(action == "OPENED" && StringLen(signalRef) > 0 && g_hbBufCount < 50)
   {
      ulong tkt = (ulong)StringToInteger(ticket);
      if(tkt > 0)
      {
         ArrayResize(g_hbRefBuf,    g_hbBufCount + 1);
         ArrayResize(g_hbTicketBuf, g_hbBufCount + 1);
         ArrayResize(g_hbSymBuf,    g_hbBufCount + 1);
         g_hbRefBuf[g_hbBufCount]    = signalRef;
         g_hbTicketBuf[g_hbBufCount] = tkt;
         g_hbSymBuf[g_hbBufCount]    = symbol;
         g_hbBufCount++;
      }
   }
}

//+------------------------------------------------------------------+
void ExecSignal(string dir, string sym, double sl, double tp, string src, double tp2=0, double tp3=0, double signalLots=0)
{
   string slInfo = (sl > 0) ? ("SL:" + DoubleToString(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS))) : "no SL";
   string tpInfo = (tp > 0) ? (" TP:" + DoubleToString(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS))) : "";
   Print("[TCU] Executing ", dir, " ", sym, " -- ", slInfo, tpInfo);
   
   // -- ARM CHECK: must be armed to place any trade ---------------------------------------
   if(!ArmExecution)
   {
      Print("[EXEC] [!] DISARMED -- signal received but NOT executing. Set ArmExecution=true to trade.");
      g_lastFilterReason = "DISARMED";
      return;
   }

   // [v6.00 FIX 2026-04-26][R7] AutoTrading permission gate. Without this, when the user
   // forgets to enable the AutoTrading button in MT5 (or AlgoTrading is disabled at terminal
   // level), every signal silently fails inside CTrade with retcode 10027/10028 and the buyer
   // thinks the EA is broken. Surface as g_lastFilterReason so the panel "Last filter reason"
   // row tells them to flip the AutoTrading button.
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      string why = !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
                   ? "AutoTrading is OFF in MT5 toolbar -- click the AutoTrading button"
                   : "AlgoTrading disabled for this EA -- enable in EA properties (Common tab)";
      Print("[EXEC] [!] ", why);
      g_lastFilterReason = why;
      DiagLog("BLOCKED", why);
      return;
   }

   if(IsNewsPauseActive(sym, true))
   {
      g_lastFilterReason = "News pause: " + g_tcuNewsLockReason;
      DiagLog("FILTERED", "News pause active for " + sym + ": " + g_tcuNewsLockReason);
      DiagSep();
      return;
   }
   
   // -- PROP FIRM MODE: enforce safety constraints ----------------------------------------
   if(PropFirmMode)
   {
      // Mandatory SL, but Auto SL counts if it can create a real stop.
      bool propAutoSLReady = (EnableAutoSL && FallbackSLPips > 0);
      if(sl <= 0 && !propAutoSLReady)
      {
          Print("[PROP] Signal rejected -- PropFirmMode requires SL. Signal has no SL: ", dir, " ", sym);
          g_lastFilterReason = "PropFirm: SL required"; DiagLog("FILTERED","PropFirmMode: SL required but missing"); DiagSep();
          g_lastError = "PropFirm: no SL in signal";
          return;
      }
      if(sl <= 0 && propAutoSLReady)
         Print("[PROP] No SL in signal for ", dir, " ", sym, " -- allowing because Auto SL fallback is enabled.");
      // No multiple open positions in same symbol+direction
      for(int pf = PositionsTotal() - 1; pf >= 0; pf--)
      {
         if(PositionGetTicket(pf) <= 0) continue;
         if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            string existDir = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";
            if(existDir == dir)
            {
               Print("[PROP] Signal rejected -- PropFirmMode: already have open ", dir, " on ", sym);
               g_lastFilterReason = "PropFirm: already open"; DiagLog("FILTERED","PropFirmMode: position already open for " + sym); DiagSep();
               return;
            }
         }
      }
   }
   
   
   // DAILY LOSS LIMIT: Check if we've exceeded the daily loss threshold
   if(TCU_EffectiveMaxDailyLossPercent() > 0 || MaxDailyLossAmount > 0)
   {
      if(IsDailyLossLimitHit())
      {
         Print("[EXEC] DAILY LOSS LIMIT HIT -- all trading suspended for today. ", dir, " ", sym, " rejected.");
         g_lastError = "Daily loss limit reached";
         g_lastFilterReason = "Daily loss limit hit";
         return;
      }
   }
   
   // SYMBOL FILTER: Check whitelist/blacklist before executing
   if(!IsSymbolAllowed(sym))
   {
      Print("[EXEC] Symbol ", sym, " blocked by symbol filter. Skipping.");
      return;
   }
   
   // Centralized ReverseSignal -- applied once here for ALL sources
   if(ReverseSignal)
   {
      if(dir == "BUY") dir = "SELL";
      else if(dir == "SELL") dir = "BUY";
   }
   
   // Circuit breaker: limit trades per minute
   ulong now = GetTickCount64();
   int effectiveTradesPerMinute = TCU_EffectiveMaxTradesPerMinute();
   if(effectiveTradesPerMinute > 0)
   {
      // Purge entries older than 60 seconds
      int newCount = 0;
      for(int i = 0; i < g_recentTradeCount; i++)
      {
         if(now - g_recentTradeTimes[i] < 60000)
            g_recentTradeTimes[newCount++] = g_recentTradeTimes[i];
      }
      g_recentTradeCount = newCount;
      ArrayResize(g_recentTradeTimes, g_recentTradeCount);
      
      if(g_recentTradeCount >= effectiveTradesPerMinute)
      {
         DiagLog("BLOCKED", "Circuit breaker: " + IntegerToString(g_recentTradeCount) + " trades in 60s (MaxTradesPerMinute=" + IntegerToString(effectiveTradesPerMinute) + ")");
         Print("[EXEC] CIRCUIT BREAKER: ", g_recentTradeCount, " trades in last 60s (max=", effectiveTradesPerMinute, "). Rejecting ", dir, " ", sym);
         g_lastError = "Circuit breaker: " + IntegerToString(effectiveTradesPerMinute) + " trades/min limit";
         return;
      }
   }
   
   // Max open positions safety cap
   // [v6.01 FIX] Count BOTH live positions AND unfilled pendings -- otherwise
   // a user with MaxOpenPositions=20 could stack 20 pendings on top of 20
   // open positions and end up with 40 trades when the pendings fill.
   int effectiveMaxOpen = TCU_EffectiveMaxOpenPositions();
   int activeCount = PositionsTotal() + OrdersTotal();
   int plannedOrders = 1;
   if(EnableMultiTP && !EnableMartingale && EnableSignalTP)
   {
      if(tp2 > 0) plannedOrders = 2;
      if(tp3 > 0) plannedOrders = 3;
      if(plannedOrders > MaxTPTargets) plannedOrders = MaxTPTargets;
   }
   if(effectiveMaxOpen > 0 && activeCount + plannedOrders > effectiveMaxOpen)
   {
      DiagLog("BLOCKED", "MaxOpenPositions=" + IntegerToString(effectiveMaxOpen) + " would be exceeded (active=" + IntegerToString(activeCount) + ", planned=" + IntegerToString(plannedOrders) + ")");
      Print("[EXEC] Max open positions would be exceeded (positions=", PositionsTotal(), " pendings=", OrdersTotal(), " planned=", plannedOrders, " cap=", effectiveMaxOpen, "). Rejecting ", dir, " ", sym);
      g_lastError = "Max positions: " + IntegerToString(effectiveMaxOpen);
      return;
   }
   
   // Enhanced cooldown -- configurable via SignalCooldownSeconds, with SL/TP modification support
   ulong cooldownMs = (ulong)SignalCooldownSeconds * 1000;
   if(cooldownMs > 0)
   {
      for(int c = 0; c < g_lastTradeCount; c++)
      {
         if(g_lastTradeSyms[c] == sym && g_lastTradeDirs[c] == dir && now - g_lastTradeTimes[c] < cooldownMs)
         {
            ulong elapsed = now - g_lastTradeTimes[c];
            
            // If signal has SL/TP and modification is allowed, modify existing position instead of blocking
            if(AllowSLTPModDuringCooldown && (sl > 0 || tp > 0))
            {
               Print("[EXEC] Cooldown active (", elapsed, "ms/", cooldownMs, "ms) but SL/TP provided. Attempting to modify existing position.");
               if(ModifyExistingPositions(sym, dir, sl, tp, src))
               {
                  Print("[EXEC] Position modified with SL/TP during cooldown. No duplicate trade opened.");
                  return;
               }
               else
               {
                  Print("[EXEC] Failed to modify existing positions, proceeding with new trade.");
                  break;
               }
            }
            
            // Cooldown active -- the #1 cause of "signal ignored" confusion!
            DiagLog("BLOCKED", "COOLDOWN: " + dir + " " + sym + " elapsed=" + IntegerToString((int)(elapsed/1000)) + "s limit=" + IntegerToString(SignalCooldownSeconds) + "s | Set SignalCooldownSeconds=0 to disable");
            Print("[EXEC] Cooldown active for ", dir, " ", sym, " (", elapsed, "ms/", cooldownMs, "ms ago). Skipping duplicate.");
            return;
         }
      }
   }
   
   // [v6.00 FIX 2026-04-26][R4] Replace blocking Sleep(500) + Sleep(1000) (1.5s worst case)
   // with bounded polls that exit the moment the symbol becomes tradeable.
   // Pre-fix: ExecSignal unconditionally Sleep'd 500ms after SymbolSelect, then 1000ms on
   // retry. ExecSignal runs on the timer thread, so those sleeps blocked PollBridge,
   // PollTelegram, ScanCopierFile and WriteMasterTrades for the entire window -- 1.5s of
   // copier latency right after every signal. Now we poll in 50ms steps, exit early on
   // success, and only burn the full window on actual failures.
   //
   // Auto-add symbol to MarketWatch if not visible
   if(!SymbolInfoInteger(sym, SYMBOL_VISIBLE))
   {
      Print("[EXEC] Adding ", sym, " to MarketWatch");
      SymbolSelect(sym, true);
      // Bounded poll up to 500ms; break the moment quotes are flowing.
      ulong addWaitEnd = GetTickCount64() + 500;
      while(GetTickCount64() < addWaitEnd)
      {
         if(SymbolInfoInteger(sym, SYMBOL_VISIBLE) && SymbolInfoDouble(sym, SYMBOL_BID) > 0)
            break;
         Sleep(50);
      }
   }
   
   // Check if symbol exists (retry once if just added)
   if(!SymbolOK(sym))
   {
      Print("[EXEC] Symbol ", sym, " not ready, retrying...");
      SymbolSelect(sym, true);
      // Bounded poll up to 1000ms; break the moment SymbolOK passes.
      ulong retryEnd = GetTickCount64() + 1000;
      while(GetTickCount64() < retryEnd && !SymbolOK(sym))
         Sleep(50);
      if(!SymbolOK(sym))
      {
         Print("[EXEC] Symbol not found after retry: ", sym);
         g_lastError = "Symbol not found: " + sym;
         DiagLog("FAILED", "Symbol not found: " + sym);
         DiagSep();
         return;
      }
      Print("[EXEC] Symbol ", sym, " loaded on retry!");
   }
   
   // TIME FILTER
   if(EnableTimeFilter)
   {
      MqlDateTime dt; TimeCurrent(dt);
      int curHour = dt.hour;
      bool inWindow = false;
      if(TimeFilterStartHour <= TimeFilterEndHour)
         inWindow = (curHour >= TimeFilterStartHour && curHour <= TimeFilterEndHour);
      else
         inWindow = (curHour >= TimeFilterStartHour || curHour <= TimeFilterEndHour);
      if(!inWindow)
      {
         Print("[EXEC] Time filter: hour=", curHour, " outside ", TimeFilterStartHour, "-", TimeFilterEndHour);
         g_lastError = "Outside time filter";
         return;
      }
   }
   
   // FALLBACK SL/TP if missing
   if(EnableAutoSL && sl <= 0 && FallbackSLPips > 0)
   {
      double pipSize = PipSize(sym);
      double currentPrice = (dir == "BUY") ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
      sl = (dir == "BUY") ? (currentPrice - FallbackSLPips * pipSize) : (currentPrice + FallbackSLPips * pipSize);
      sl = NormalizeDouble(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
      Print("[EXEC] Using Auto SL: ", DoubleToString(sl, 5));
   }
   if(EnableAutoTP && tp <= 0 && FallbackTPPips > 0)
   {
      double pipSize = PipSize(sym);
      double currentPrice = (dir == "BUY") ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
      tp = (dir == "BUY") ? (currentPrice + FallbackTPPips * pipSize) : (currentPrice - FallbackTPPips * pipSize);
      tp = NormalizeDouble(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
      Print("[EXEC] Using Auto TP: ", DoubleToString(tp, 5));
   }

   // SKIP WITHOUT SL/TP
   if(SkipSignalWithoutSL && sl <= 0) { g_lastFilterReason = "No SL (SkipWSL=true)"; Print("[EXEC] No SL - skipping"); DiagLog("FILTERED","No SL on signal (SkipSignalWithoutSL=true)"); DiagSep(); g_lastError = "No SL"; return; }
   if(SkipSignalWithoutTP && tp <= 0) { g_lastFilterReason = "No TP (SkipWTP=true)"; Print("[EXEC] No TP - skipping"); DiagLog("FILTERED","No TP on signal (SkipSignalWithoutTP=true)"); DiagSep(); g_lastError = "No TP"; return; }
   
   // OPPOSITE ORDER ACTION
   if(OppositeAction != OPP_NOTHING)
   {
      for(int op = PositionsTotal() - 1; op >= 0; op--)
      {
         if(PositionGetTicket(op) <= 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         bool opIsBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         bool isOpp = (OppositeAction == OPP_CLOSE_ALL) ||
                      ((dir == "BUY" && !opIsBuy) || (dir == "SELL" && opIsBuy));
         if(isOpp)
         {
            ulong _oppTkt = PositionGetTicket(op);
            Print("[EXEC] Closing opposite #", _oppTkt);
            bool _closed = g_trade.PositionClose(_oppTkt);
            if(!_closed)
            {
               Sleep(200);
               _closed = g_trade.PositionClose(_oppTkt); // retry once
               if(!_closed) Print("[EXEC] WARNING: opposite close retry failed for #", _oppTkt);
            }
            if(_closed && EnableMartingale)
            {
               ulong _closeDeal = g_trade.ResultDeal();
               if(_closeDeal > 0 && !MG_IsDealProcessed(_closeDeal) && HistoryDealSelect(_closeDeal))
               {
                  double _dpRaw = HistoryDealGetDouble(_closeDeal, DEAL_PROFIT);
                  double _dp = _dpRaw
                             + HistoryDealGetDouble(_closeDeal, DEAL_SWAP)
                             + HistoryDealGetDouble(_closeDeal, DEAL_COMMISSION);
                  MG_MarkDealProcessed(_closeDeal);
                  MG_OnClose(sym, _dp, true, false, _dpRaw);
               }
            }
         }
      }
   }
   
   // PIPS DISTANCE DEDUP
   if(EnableDuplicateFilter && MinPipsDistanceSameType > 0)
   {
      double dedupPipSz = PipSize(sym);
      for(int dp = PositionsTotal() - 1; dp >= 0; dp--)
      {
         if(PositionGetTicket(dp) <= 0 || PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != sym) continue;
         bool dpIsBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         if((dir == "BUY" && dpIsBuy) || (dir == "SELL" && !dpIsBuy))
         {
            double existEntry = PositionGetDouble(POSITION_PRICE_OPEN);
            double curPrice2 = dpIsBuy ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
            double distPips = MathAbs(curPrice2 - existEntry) / dedupPipSz;
            if(distPips < MinPipsDistanceSameType)
            {
               Print("[EXEC] Too close (", DoubleToString(distPips,1), " pips). Skip.");
               g_lastError = "Too close: " + DoubleToString(distPips, 1) + " pips";
               return;
            }
         }
      }
   }
   
   int spread = (int)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   int effectiveMaxSpread = TCU_EffectiveMaxSpreadPoints();
   if(TCU_EffectiveSpreadFilterEnabled())
   {
      Print("[EXEC] Spread: ", spread, " (max: ", effectiveMaxSpread, ")");
      if(spread > effectiveMaxSpread)
      {
         g_lastError = "Spread: " + IntegerToString(spread);
         Print("[EXEC] Spread too high! ", spread, " > ", effectiveMaxSpread);
         DoAlert("Signal skipped - spread: " + IntegerToString(spread));
         return;
      }
   }
   
      // [v6.01 FIX] Pass direction so CalcLots uses BID for SELL signals.
      double lots = CalcLots(sym, sl, signalLots, dir, tp);
   Print("[EXEC] Lots: ", DoubleToString(lots, 2));
   if(SkipIfLotOverMax && lots > MaxLotSize) { Print("[EXEC] Lot too large - skipping"); g_lastError = "Lot too large"; return; }
   
   // ARMOR: SL SANITY CHECK -- reject signals where SL is on wrong side of price
   double checkPrice = (dir == "BUY") ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   if(sl > 0)
   {
      if(dir == "BUY" && sl >= checkPrice)
      {
         Print("[EXEC] SL SANITY FAIL: BUY signal with SL (", sl, ") above current price (", checkPrice, "). Rejecting.");
         g_lastError = "Invalid SL for BUY";
         return;
      }
      if(dir == "SELL" && sl <= checkPrice)
      {
         Print("[EXEC] SL SANITY FAIL: SELL signal with SL (", sl, ") below current price (", checkPrice, "). Rejecting.");
         g_lastError = "Invalid SL for SELL";
         return;
      }
   }
   
   // ARMOR: PRE-TRADE MARGIN CHECK -- don't send orders the broker will reject.
   // In Signal TP fixed-lot override mode the combined TP legs can exceed the
   // base `lots` value, so validate the actual planned legs instead of only the
   // pre-split parent size.
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   ENUM_ORDER_TYPE marginCheckType = (dir == "BUY") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   bool previewMultiTp = (EnableMultiTP && !EnableMartingale && EnableSignalTP && (tp2 > 0 || tp3 > 0));
   if(previewMultiTp)
   {
      int previewTPs = 1;
      if(tp2 > 0) previewTPs = 2;
      if(tp3 > 0) previewTPs = 3;
      if(previewTPs > MaxTPTargets) previewTPs = MaxTPTargets;
      double previewLots[3];
      ArrayInitialize(previewLots, 0.0);
      if(!TCU_BuildSignalTpLots(sym, lots, previewTPs, previewLots[0], previewLots[1], previewLots[2], "MARGINCHK"))
      {
         g_lastError = "Signal TP lots invalid";
         return;
      }
      double totalMarginRequired = 0;
      for(int mi = 0; mi < previewTPs; mi++)
      {
         double legMargin = 0;
         if(previewLots[mi] <= 0) continue;
         if(OrderCalcMargin(marginCheckType, sym, previewLots[mi], checkPrice, legMargin))
            totalMarginRequired += legMargin;
      }
      if(totalMarginRequired > 0 && freeMargin < totalMarginRequired)
      {
         Print("[EXEC] MARGIN CHECK FAIL: Need $", DoubleToString(totalMarginRequired, 2), ", Have $", DoubleToString(freeMargin, 2),
               " for split TP legs.");
         g_lastError = "Insufficient margin";
         DoAlert("Margin too low to copy: " + dir + " " + sym);
         return;
      }
   }
   double marginRequired = 0;
   if(OrderCalcMargin(marginCheckType, sym, lots, checkPrice, marginRequired))
   {
      if(freeMargin < marginRequired)
      {
         Print("[EXEC] MARGIN CHECK FAIL: Need $", DoubleToString(marginRequired, 2), ", Have $", DoubleToString(freeMargin, 2));
         g_lastError = "Insufficient margin";
         DoAlert("Margin too low to copy: " + dir + " " + sym);
         return;
      }
   }
   
   // Get symbol info for normalization
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minStop = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   
   // Normalize SL/TP to correct digits
   double normSL = 0;
   double normTP = 0;
   
   if(sl > 0 && CopySL)
   {
      normSL = NormalizeDouble(sl, digits);
   }
   if(tp > 0 && CopyTP)
   {
      normTP = NormalizeDouble(tp, digits);
   }
   
   Print("[EXEC] Normalized SL:", DoubleToString(normSL, digits), " TP:", DoubleToString(normTP, digits), " (digits:", digits, ")");
   
   bool ok = false;
   double price = 0;
   
   // MULTI-TP SPLITTING: If extra signal TPs are provided and Multi TP enabled, split into multiple trades
    if(EnableMultiTP && !EnableMartingale && EnableSignalTP && (tp2 > 0 || tp3 > 0))
    {
       int numTPs = 1;
       if(tp2 > 0) numTPs = 2;
       if(tp3 > 0) numTPs = 3;
       if(numTPs > MaxTPTargets) numTPs = MaxTPTargets;
       
       double tpLots[3];
       ArrayInitialize(tpLots, 0.0);
       if(!TCU_BuildSignalTpLots(sym, lots, numTPs, tpLots[0], tpLots[1], tpLots[2], "MULTI-TP"))
       {
          g_lastError = "Signal TP lots invalid";
          return;
       }
       if(numTPs == 1)
       {
          Print("[MULTI-TP] Collapsed to one affordable leg.");
          tp2 = 0;
          tp3 = 0;
       }
      
      double tps[3]; tps[0] = tp; tps[1] = tp2; tps[2] = tp3;
      string groupID = IntegerToString(GetTickCount64());
      int placed = 0;
      
      // Pre-validate: count how many TPs are on the correct side of market
      double curBid = SymbolInfoDouble(sym, SYMBOL_BID);
      double curAsk = SymbolInfoDouble(sym, SYMBOL_ASK);
      int validTPCount = 0;
      for(int v = 0; v < numTPs; v++)
      {
         double tv = tps[v];
         if(tv <= 0) continue;
         if(dir == "BUY"  && tv > curAsk) validTPCount++;
         if(dir == "SELL" && tv < curBid) validTPCount++;
      }
      if(validTPCount == 0)
      {
         Print("[MULTI-TP] ABORTED — all ", numTPs, " TP levels are on the wrong side of market (",
               dir, " @ ", DoubleToString(dir=="BUY"?curAsk:curBid, digits),
               "). Signal prices appear stale. No trades opened.");
         g_lastError = "MULTI-TP aborted: all TPs wrong side";
         return;
      }
      if(validTPCount < numTPs)
         Print("[MULTI-TP] Warning: ", numTPs - validTPCount, " of ", numTPs, " TP levels are on wrong side and will be skipped.");
      
      Print("[MULTI-TP] Splitting ", DoubleToString(lots, 2), " lots into ", numTPs, " positions");
      
      ulong batchTickets[];
      for(int t = 0; t < numTPs; t++)
      {
         double tpLot = tpLots[t];
         double tpVal = tps[t];
         double tpNorm = NormalizeDouble(tpVal, digits);
         
         // Skip this leg if its TP is on the wrong side
         if(tpNorm > 0)
         {
            if(dir == "BUY"  && tpNorm <= curBid) { Print("[MULTI-TP] TP", t+1, " skipped (wrong side: ", DoubleToString(tpNorm,digits), " <= bid)"); continue; }
            if(dir == "SELL" && tpNorm >= curAsk) { Print("[MULTI-TP] TP", t+1, " skipped (wrong side: ", DoubleToString(tpNorm,digits), " >= ask)"); continue; }
         }
         // [v6.x FIX] Open each leg WITH its SL/TP so no leg is ever naked.
         double legWantSL = (normSL > 0 && CopySL) ? normSL : 0;
         double legWantTP = (CopyTP && tpNorm > 0) ? tpNorm : 0;
         double legSafeSL = 0, legSafeTP = 0;
         bool   legProtected = false;
         if(legWantSL > 0 || legWantTP > 0)
         {
            string legPrepNote = "";
            TCU_PrepareSafeAttachLevels(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL,
                                        legWantSL, legWantTP, legSafeSL, legSafeTP, legPrepNote);
         }

         bool tok = false;
         if(dir == "BUY")
         {
            price = NormalizeDouble(SymbolInfoDouble(sym, SYMBOL_ASK), digits);
            tok = g_trade.Buy(tpLot, sym, price, legSafeSL, legSafeTP, TCU_TradeComment(src + "_TP" + IntegerToString(t+1)));
            legProtected = (tok && (legSafeSL > 0 || legSafeTP > 0));
            if(!tok && (legSafeSL > 0 || legSafeTP > 0))
            {
               price = NormalizeDouble(SymbolInfoDouble(sym, SYMBOL_ASK), digits);
               tok = g_trade.Buy(tpLot, sym, price, 0, 0, TCU_TradeComment(src + "_TP" + IntegerToString(t+1)));
            }
         }
         else if(dir == "SELL")
         {
            price = NormalizeDouble(SymbolInfoDouble(sym, SYMBOL_BID), digits);
            tok = g_trade.Sell(tpLot, sym, price, legSafeSL, legSafeTP, TCU_TradeComment(src + "_TP" + IntegerToString(t+1)));
            legProtected = (tok && (legSafeSL > 0 || legSafeTP > 0));
            if(!tok && (legSafeSL > 0 || legSafeTP > 0))
            {
               price = NormalizeDouble(SymbolInfoDouble(sym, SYMBOL_BID), digits);
               tok = g_trade.Sell(tpLot, sym, price, 0, 0, TCU_TradeComment(src + "_TP" + IntegerToString(t+1)));
            }
         }

         if(tok)
         {
            placed++;
            Print("[MULTI-TP] TP", t+1, ": ", DoubleToString(tpLot, 2), " lots, TP=", tpNorm);
            ulong orderTicket = g_trade.ResultOrder();
            ulong dealTicket = g_trade.ResultDeal();
            ulong tkt = WaitForUniquePositionTicketFromTradeResult(
               sym,
               dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL,
               orderTicket,
               dealTicket,
               batchTickets,
               1500
            );
            if(tkt > 0)
            {
               int bt = ArraySize(batchTickets);
               ArrayResize(batchTickets, bt + 1);
               batchTickets[bt] = tkt;
            }
            // Attach SL/TP only if the leg was NOT opened protected above.
            if(!legProtected && (legWantSL > 0 || legWantTP > 0))
            {
               double atSL = legWantSL, atTP = legWantTP;
               string attachAdjustNote = "";
               TCU_PrepareSafeAttachLevels(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, atSL, atTP, atSL, atTP, attachAdjustNote);
               if(StringLen(attachAdjustNote) > 0)
                  Print("[MULTI-TP] Attach levels adjusted for ", sym, " TP", t+1, ": ", attachAdjustNote);
               if(tkt > 0 && PositionSelectByTicket(tkt))
               {
                  if(!g_trade.PositionModify(tkt, atSL, atTP))
                     QueuePendingSLTPAttach(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, orderTicket, dealTicket, tkt, atSL, atTP, "MULTITP_TP" + IntegerToString(t + 1));
               }
               else
               {
                  Print("[MULTI-TP] Could not resolve live position ticket for TP", t+1, " SL/TP attach");
                  QueuePendingSLTPAttach(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, orderTicket, dealTicket, tkt, atSL, atTP, "MULTITP_TP" + IntegerToString(t + 1));
               }
            }
            // Register for ManageMultiTP tracking
            int mi = g_mtpCount; g_mtpCount++;
            ArrayResize(g_mtpGroupIDs, g_mtpCount); ArrayResize(g_mtpTickets, g_mtpCount);
            ArrayResize(g_mtpTPIndex, g_mtpCount); ArrayResize(g_mtpTPPrices, g_mtpCount);
            ArrayResize(g_mtpEntryPrices, g_mtpCount);
            g_mtpGroupIDs[mi] = groupID; g_mtpTickets[mi] = tkt;
            g_mtpTPIndex[mi] = t + 1; g_mtpTPPrices[mi] = tpNorm;
            g_mtpEntryPrices[mi] = price;
            
            // Register for manual partial close tracking
            if(EnablePartialClose && (PartialTP1Pips > 0 || PartialTP2Pips > 0 || PartialTP3Pips > 0 || PartialTP4Pips > 0))
            {
               int pi = g_partialCount; g_partialCount++;
               ArrayResize(g_partialTickets, g_partialCount);
               ArrayResize(g_partialTP1Done, g_partialCount);
               ArrayResize(g_partialTP2Done, g_partialCount);
               ArrayResize(g_partialTP3Done, g_partialCount);
               ArrayResize(g_partialTP4Done, g_partialCount);
               ArrayResize(g_partialOrigLots, g_partialCount);
               g_partialTickets[pi] = tkt;
               g_partialTP1Done[pi] = false; g_partialTP2Done[pi] = false; g_partialTP3Done[pi] = false; g_partialTP4Done[pi] = false;
               g_partialOrigLots[pi] = tpLot;
               Print("[PARTIAL] Registered multi-TP ticket #", tkt, " for partial close tracking");
            }
         }
      }
      
      if(placed > 0)
      {
         g_tradesReceived += placed;
         g_lastError = "";
         g_signalsProcessed++;
         // [v6.00 FIX 2026-04-26][R2] Multi-TP execution succeeded -- persist dedup hash now.
         if(g_currentSignalHash != 0) { MarkProcessed(g_currentSignalHash); g_currentSignalHash = 0; }
         Print("[MULTI-TP] Placed ", placed, "/", numTPs, " positions for ", sym);
         DoAlert(src + ": " + dir + " " + sym + " " + IntegerToString(placed) + "x multi-TP");
         // Ticket callback: report each placed leg back to bridge
         if(StringLen(g_currentSignalRef) > 0)
         {
            int bSize = ArraySize(batchTickets);
            for(int bi = 0; bi < bSize; bi++)
               SendBridgeCallback(g_currentSignalRef, IntegerToString(batchTickets[bi]), "OPENED", sym);
            g_currentSignalRef = "";
         }
         
         // Record cooldown
         int idx = -1;
         for(int c = 0; c < g_lastTradeCount; c++)
            if(g_lastTradeSyms[c] == sym && g_lastTradeDirs[c] == dir) { idx = c; break; }
         if(idx < 0) { idx = g_lastTradeCount; g_lastTradeCount++; }
         ArrayResize(g_lastTradeSyms, g_lastTradeCount);
         ArrayResize(g_lastTradeDirs, g_lastTradeCount);
         ArrayResize(g_lastTradeTimes, g_lastTradeCount);
         g_lastTradeSyms[idx] = sym; g_lastTradeDirs[idx] = dir;
         g_lastTradeTimes[idx] = GetTickCount64();
         
         // Circuit breaker counts one accepted signal, not each TP leg.
         ArrayResize(g_recentTradeTimes, g_recentTradeCount + 1);
         g_recentTradeTimes[g_recentTradeCount++] = GetTickCount64();
      }
      else
      {
         g_lastError = "Multi-TP: all failed";
         Print("[MULTI-TP] All trades failed!");
      }
      return; // Multi-TP handled -- don't fall through to single trade
   }
   
   // SINGLE TRADE: Normal execution
   // Pre-check: if signal provided a TP but it is on the wrong side of current price, abort
   if(normTP > 0 && CopyTP)
   {
      double sBid = SymbolInfoDouble(sym, SYMBOL_BID);
      double sAsk = SymbolInfoDouble(sym, SYMBOL_ASK);
      bool tpWrongSide = (dir == "BUY"  && normTP <= sBid) ||
                         (dir == "SELL" && normTP >= sAsk);
      if(tpWrongSide)
      {
         Print("[EXEC] ABORTED — TP ", DoubleToString(normTP, digits),
               " is on the wrong side of market (", dir, " @ ",
               DoubleToString(dir=="BUY"?sAsk:sBid, digits),
               "). Signal prices appear stale. Trade not opened.");
         g_lastError = "Aborted: TP wrong side of market";
         return;
      }
   }
   
   // [v6.x FIX] Open the position WITH its SL/TP in the initial order so it is
   // never naked. Broker-safe levels are computed first; only if the protected
   // order is rejected do we fall back to a naked open + deferred attach.
   double wantSL = (normSL > 0 && CopySL) ? normSL : 0;
   double wantTP = (normTP > 0 && CopyTP) ? normTP : 0;
   double safeSL = 0, safeTP = 0;
   bool   openedProtected = false;
   if(wantSL > 0 || wantTP > 0)
   {
      string prepNote = "";
      TCU_PrepareSafeAttachLevels(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL,
                                  wantSL, wantTP, safeSL, safeTP, prepNote);
      if(StringLen(prepNote) > 0)
         Print("[EXEC] Entry SL/TP adjusted for ", sym, ": ", prepNote);
   }

   if(dir == "BUY")
   {
      price = NormalizeDouble(SymbolInfoDouble(sym, SYMBOL_ASK), digits);
      DiagLog("PARSED", "dir=" + dir + " sym=" + sym + " lots=" + DoubleToString(lots,2) + " SL=" + DoubleToString(sl,5) + " TP=" + DoubleToString(tp,5));
      Print("[EXEC] BUY at ", price, " SL=", DoubleToString(safeSL,digits), " TP=", DoubleToString(safeTP,digits));
      ok = g_trade.Buy(lots, sym, price, safeSL, safeTP, TCU_TradeComment(src));
      openedProtected = (ok && (safeSL > 0 || safeTP > 0));
      if(!ok && (safeSL > 0 || safeTP > 0))
      {
         Print("[EXEC] Protected open rejected (", g_trade.ResultRetcode(), ") -- retrying naked, SL/TP will attach after");
         price = NormalizeDouble(SymbolInfoDouble(sym, SYMBOL_ASK), digits);
         ok = g_trade.Buy(lots, sym, price, 0, 0, TCU_TradeComment(src));
      }
   }
   else if(dir == "SELL")
   {
      price = NormalizeDouble(SymbolInfoDouble(sym, SYMBOL_BID), digits);
      Print("[EXEC] SELL at ", price, " SL=", DoubleToString(safeSL,digits), " TP=", DoubleToString(safeTP,digits));
      ok = g_trade.Sell(lots, sym, price, safeSL, safeTP, TCU_TradeComment(src));
      openedProtected = (ok && (safeSL > 0 || safeTP > 0));
      if(!ok && (safeSL > 0 || safeTP > 0))
      {
         Print("[EXEC] Protected open rejected (", g_trade.ResultRetcode(), ") -- retrying naked, SL/TP will attach after");
         price = NormalizeDouble(SymbolInfoDouble(sym, SYMBOL_BID), digits);
         ok = g_trade.Sell(lots, sym, price, 0, 0, TCU_TradeComment(src));
      }
   }
   
   if(ok)
   {
      ulong resultOrderTicket = g_trade.ResultOrder();
      ulong resultDealTicket = g_trade.ResultDeal();
      ulong liveTicket = ResolvePositionTicketFromTradeResult(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, resultOrderTicket, resultDealTicket);
      g_tradesReceived++;
      g_lastError = "";
      // [v6.00 FIX 2026-04-26][R2] Single-trade execution succeeded -- persist dedup hash now.
      if(g_currentSignalHash != 0) { MarkProcessed(g_currentSignalHash); g_currentSignalHash = 0; }
      Print("[EXEC] SUCCESS! ", dir, " ", sym, " ", DoubleToString(lots, 2), " lots");
      DiagLog("EXECUTED", dir + " " + sym + " lots=" + DoubleToString(lots,2)
         + " price=" + DoubleToString(g_trade.ResultPrice(), (int)SymbolInfoInteger(sym,SYMBOL_DIGITS))
         + " ticket=#" + IntegerToString(resultOrderTicket)
         + (sl>0 ? " SL=" + DoubleToString(sl, (int)SymbolInfoInteger(sym,SYMBOL_DIGITS)) : "")
         + (tp>0 ? " TP=" + DoubleToString(tp, (int)SymbolInfoInteger(sym,SYMBOL_DIGITS)) : ""));
      DiagSep();
      DoAlert(src + ": " + dir + " " + sym + " " + DoubleToString(lots, 2) + " lots");
      // Ticket callback: report opened ticket back to bridge
      if(StringLen(g_currentSignalRef) > 0)
      {
         ulong cbTicket = (liveTicket > 0) ? liveTicket : resultOrderTicket;
         SendBridgeCallback(g_currentSignalRef, IntegerToString(cbTicket), "OPENED", sym);
         g_currentSignalRef = "";
      }
      
      // Register for manual partial close tracking
      if(EnablePartialClose && (PartialTP1Pips > 0 || PartialTP2Pips > 0 || PartialTP3Pips > 0 || PartialTP4Pips > 0))
      {
         ulong regTicket = liveTicket;
         if(regTicket > 0)
         {
            int pi = g_partialCount; g_partialCount++;
            ArrayResize(g_partialTickets, g_partialCount);
            ArrayResize(g_partialTP1Done, g_partialCount);
            ArrayResize(g_partialTP2Done, g_partialCount);
            ArrayResize(g_partialTP3Done, g_partialCount);
            ArrayResize(g_partialTP4Done, g_partialCount);
            ArrayResize(g_partialOrigLots, g_partialCount);
            g_partialTickets[pi] = regTicket;
            g_partialTP1Done[pi] = false; g_partialTP2Done[pi] = false; g_partialTP3Done[pi] = false; g_partialTP4Done[pi] = false;
            g_partialOrigLots[pi] = lots;
            Print("[PARTIAL] Registered ticket #", regTicket, " for partial close tracking");
         }
      }
      
      // Record cooldown
      int idx = -1;
      for(int c = 0; c < g_lastTradeCount; c++)
         if(g_lastTradeSyms[c] == sym && g_lastTradeDirs[c] == dir) { idx = c; break; }
      if(idx < 0) { idx = g_lastTradeCount; g_lastTradeCount++; }
      ArrayResize(g_lastTradeSyms, g_lastTradeCount);
      ArrayResize(g_lastTradeDirs, g_lastTradeCount);
      ArrayResize(g_lastTradeTimes, g_lastTradeCount);
      g_lastTradeSyms[idx] = sym;
      g_lastTradeDirs[idx] = dir;
      g_lastTradeTimes[idx] = GetTickCount64();
      
      // Circuit breaker: record this trade
      ArrayResize(g_recentTradeTimes, g_recentTradeCount + 1);
      g_recentTradeTimes[g_recentTradeCount] = GetTickCount64();
      g_recentTradeCount++;
      
      // Add SL/TP by ticket -- only needed if the protected open was rejected
      // above and we fell back to a naked open.
      if(!openedProtected && ((normSL > 0 && CopySL) || (normTP > 0 && CopyTP)))
      {
         string attachAdjustNote = "";
         TCU_PrepareSafeAttachLevels(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, normSL, normTP, normSL, normTP, attachAdjustNote);
         if(StringLen(attachAdjustNote) > 0)
            Print("[EXEC] Attach levels adjusted for ", sym, ": ", attachAdjustNote);
         bool queuedRetry = false;
         if(liveTicket > 0 && PositionSelectByTicket(liveTicket))
         {
            if(g_trade.PositionModify(liveTicket, normSL, normTP))
               Print("[EXEC] SL/TP added: SL=", normSL, " TP=", normTP);
            else
            {
               Print("[EXEC] Could not add SL/TP (code: ", g_trade.ResultRetcode(), ") - trade opened without them");
               QueuePendingSLTPAttach(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, resultOrderTicket, resultDealTicket, liveTicket, normSL, normTP, "EXEC_SINGLE");
               queuedRetry = true;
            }
         }
         else
         {
            Print("[EXEC] Could not resolve/select live position for SL/TP attach");
            QueuePendingSLTPAttach(sym, dir == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, resultOrderTicket, resultDealTicket, liveTicket, normSL, normTP, "EXEC_SINGLE");
            queuedRetry = true;
         }
         if(queuedRetry)
            Print("[EXEC] SL/TP attach queued for retry");
      }
   }
   else
   {
      int retcode = (int)g_trade.ResultRetcode();
      g_lastError = "Trade fail: " + IntegerToString(retcode);
      Print("[EXEC] FAILED! Retcode: ", retcode, " - ", g_trade.ResultComment());
      DoAlert("Trade failed! " + sym + " Code: " + IntegerToString(retcode));
   }
}

//+------------------------------------------------------------------+
// [v6.00 NEW][PerSymbolLots] Helpers and resolver for per-symbol lot overrides.
//
// PerSymbolLots is a free-form input string of the form:
//   "EURUSD=0.05, XAUUSD=0.03, GBPUSD=0.02, NAS100=0.10"
//
// Rules:
//   - Whitespace around '=' and ',' is trimmed.
//   - Symbol match is case-insensitive.
//   - Up to TCU_PERSYMBOL_MAX (20) entries are honoured. Anything past 20 is ignored
//     with a single warning at parse time -- prevents giant pasted strings from
//     overloading the per-signal lookup path.
//   - Entries whose symbol is NOT visible in MarketWatch are skipped (logged once).
//     This prevents typos like "EURUSED=0.05" from silently confusing the buyer.
//   - Suffix-tolerant: a typed key of "XAUUSD" matches a signal symbol of "XAUUSD.m"
//     or "XAUUSD.pro" (broker suffix). Match is restricted by a non-letter boundary
//     after the key so "EUR" does not accidentally match every EUR pair.
//   - First matching entry wins. Later duplicates ignored.
//   - If the value parses to <= 0 the entry is skipped.
//
// On match, normal LotMode (Fixed/RiskPercent) is bypassed entirely. Min/max/step
// normalization and SkipIfLotOverMax / MaxLotSize clamps still apply afterwards.
// (TCU_PERSYMBOL_MAX is now hoisted to the modal globals block; this guard is here
// only so the legacy validator code below still compiles if hoist is removed.)
#ifndef TCU_PERSYMBOL_MAX
#define TCU_PERSYMBOL_MAX 20
#endif

// Returns true if `sym` is currently selected in MarketWatch.
bool TCU_IsInMarketWatch(string sym)
{
   if(StringLen(sym) == 0) return false;
   // SymbolInfoInteger(SYMBOL_SELECT) is true if the symbol is in MarketWatch.
   // We also try a prefix scan over MarketWatch in case the user typed a key without
   // the broker suffix. Caller should pass the resolved (suffix-included) name when
   // possible.
   if(SymbolInfoInteger(sym, SYMBOL_SELECT) > 0) return true;
   string symU = sym; StringToUpper(symU);
   int total = SymbolsTotal(true);  // selected (MarketWatch) only
   for(int i = 0; i < total; i++)
   {
      string mw = SymbolName(i, true);
      string mwU = mw; StringToUpper(mwU);
      if(mwU == symU) return true;
      // prefix-with-boundary match, see GetPerSymbolLot for matching rules
      if(StringFind(mwU, symU) == 0 && StringLen(mwU) > StringLen(symU))
      {
         ushort nx = StringGetCharacter(mwU, StringLen(symU));
         bool isLetter = (nx >= 'A' && nx <= 'Z') || (nx >= 'a' && nx <= 'z');
         if(!isLetter) return true;
      }
   }
   return false;
}

// Returns active entry count after parsing -- used by the panel to show "Per-Sym: N/M active".
// Logs warnings for entries that fail validation (typo, not-in-MarketWatch, bad value, over cap).
int PerSymbolLots_ValidateAndCount(bool logWarnings)
{
   if(StringLen(PerSymbolLots) == 0) return 0;
   string entries[];
   int n = StringSplit(PerSymbolLots, ',', entries);
   int active = 0;
   int skipped = 0;
   for(int i = 0; i < n; i++)
   {
      if(active >= TCU_PERSYMBOL_MAX)
      {
         if(logWarnings) Print("[LOTS] Per-symbol cap reached (", TCU_PERSYMBOL_MAX, " entries) -- ignoring rest of PerSymbolLots");
         break;
      }
      string kv = entries[i];
      StringTrimLeft(kv); StringTrimRight(kv);
      if(StringLen(kv) == 0) continue;
      int eq = StringFind(kv, "=");
      if(eq <= 0) {
         if(logWarnings) Print("[LOTS] Per-symbol entry skipped (missing '='): \"", kv, "\"");
         skipped++; continue;
      }
      string key = StringSubstr(kv, 0, eq);
      string val = StringSubstr(kv, eq + 1);
      StringTrimLeft(key); StringTrimRight(key);
      StringTrimLeft(val); StringTrimRight(val);
      if(StringLen(key) == 0) continue;
      double lot = StringToDouble(val);
      if(lot <= 0) {
         if(logWarnings) Print("[LOTS] Per-symbol entry skipped (bad lot value): \"", kv, "\"");
         skipped++; continue;
      }
      if(!TCU_IsInMarketWatch(key))
      {
         if(logWarnings) Print("[LOTS] Per-symbol entry \"", key, "=", val, "\" skipped -- not in MarketWatch (typo? add the symbol to MarketWatch first)");
         skipped++; continue;
      }
      active++;
   }
   return active;
}

// MG per-symbol base lot hot path. Returns the override base lot, or 0 if no match.
// Same parse logic as GetPerSymbolLot but reads from MGPerSymbolLots.
double GetMGPerSymbolBaseLot(string sym)
{
   if(StringLen(MGPerSymbolLots) == 0) return 0;
   string symU = sym; StringToUpper(symU);
   string entries[];
   int n = StringSplit(MGPerSymbolLots, ',', entries);
   for(int i = 0; i < n && i < TCU_PERSYMBOL_MAX; i++)
   {
      string kv = entries[i];
      StringTrimLeft(kv); StringTrimRight(kv);
      if(StringLen(kv) == 0) continue;
      int eq = StringFind(kv, "=");
      if(eq <= 0) continue;
      string key = StringSubstr(kv, 0, eq);
      string val = StringSubstr(kv, eq + 1);
      StringTrimLeft(key); StringTrimRight(key);
      StringTrimLeft(val); StringTrimRight(val);
      if(StringLen(key) == 0 || StringLen(val) == 0) continue;
      double lot = StringToDouble(val);
      if(lot <= 0) continue;
      string keyU = key; StringToUpper(keyU);
      if(symU == keyU) return lot;
      int keyLen = StringLen(keyU);
      if(keyLen > 0 && StringFind(symU, keyU) == 0 && StringLen(symU) > keyLen)
      {
         ushort nx = StringGetCharacter(symU, keyLen);
         bool isLetter = (nx >= 'A' && nx <= 'Z') || (nx >= 'a' && nx <= 'z');
         if(!isLetter) return lot;
      }
   }
   return 0;
}

// Per-signal hot path. Returns the override lot value, or 0 if no match.
double GetPerSymbolLot(string sym)
{
   if(StringLen(PerSymbolLots) == 0) return 0;

   string symU = sym; StringToUpper(symU);
   string entries[];
   int n = StringSplit(PerSymbolLots, ',', entries);
   int active = 0;
   for(int i = 0; i < n && active < TCU_PERSYMBOL_MAX; i++)
   {
      string kv = entries[i];
      StringTrimLeft(kv); StringTrimRight(kv);
      if(StringLen(kv) == 0) continue;
      int eq = StringFind(kv, "=");
      if(eq <= 0) continue;
      string key = StringSubstr(kv, 0, eq);
      string val = StringSubstr(kv, eq + 1);
      StringTrimLeft(key); StringTrimRight(key);
      StringTrimLeft(val); StringTrimRight(val);
      if(StringLen(key) == 0 || StringLen(val) == 0) continue;
      double lot = StringToDouble(val);
      if(lot <= 0) continue;
      // MarketWatch validation (per the requirement: only MarketWatch symbols are honoured).
      if(!TCU_IsInMarketWatch(key)) continue;
      active++;

      // Match logic:
      //   1) exact case-insensitive match
      //   2) signal-symbol starts with key AND next char is non-letter (broker suffix boundary)
      string keyU = key; StringToUpper(keyU);
      if(symU == keyU) return lot;
      int keyLen = StringLen(keyU);
      if(keyLen > 0 && StringFind(symU, keyU) == 0 && StringLen(symU) > keyLen)
      {
         ushort nx = StringGetCharacter(symU, keyLen);
         bool isLetter = (nx >= 'A' && nx <= 'Z') || (nx >= 'a' && nx <= 'z');
         if(!isLetter) return lot;
      }
   }
   return 0;
}

// ===========================================================================
// MARTINGALE HELPERS
// Mode 0 = Classic    : lots * 2^streak
// Mode 1 = Custom     : lots * customMultiplier^streak
// Mode 2 = AntiMartin : lots * multiplier^streak (on WIN streak, not loss)
// Mode 3 = FixedStep  : lots + (fixedStep * streak)
// Reset triggers:
//   - MaxSteps reached        -> always resets
//   - MaxLotSize cap hit      -> always resets
//   - Win (if ResetOnWin=true)
// ===========================================================================

int MG_Find(string sym)
{
   for(int i = 0; i < g_mgCount; i++)
      if(g_mgTable[i].sym == sym) return i;
   return -1;
}

int MG_GetOrCreate(string sym)
{
   int idx = MG_Find(sym);
   if(idx >= 0) return idx;
   idx = g_mgCount++;
   ArrayResize(g_mgTable, g_mgCount);
   g_mgTable[idx].sym       = sym;
   g_mgTable[idx].streak    = 0;
   g_mgTable[idx].mgPnl     = 0;
   g_mgTable[idx].wins      = 0;
   g_mgTable[idx].losses    = 0;
   g_mgTable[idx].lastPnl   = 0;
   g_mgTable[idx].carry     = 0;
   g_mgTable[idx].recTarget = 0;
   return idx;
}

int MG_GetStreak(string sym)
{
   int idx = MG_Find(sym);
   return (idx >= 0) ? g_mgTable[idx].streak : 0;
}

string MG_ModeText()
{
   switch(MartingaleMode)
   {
      case 0: return "Classic x2";
      case 1: return "Custom x" + DoubleToString(MartingaleMultiplier, 2);
      case 2: return "Anti-Martin";
      case 3: return "Fixed +" + DoubleToString(MartingaleFixedStep, 2);
      case 4: return "Advanced";
   }
   return "Off";
}

void MG_ClearDealCache()
{
   ArrayInitialize(g_mgProcessedDeals, 0);
   g_mgProcessedHead = 0;
}

datetime MG_HistoryFloor()
{
   return (g_mgActivationTime > 0) ? g_mgActivationTime : (TimeCurrent() - 86400);
}

void MG_StartFreshSeries(string reason = "")
{
   for(int i = 0; i < g_mgCount; i++)
   {
      g_mgTable[i].streak    = 0;
      g_mgTable[i].mgPnl     = 0;
      g_mgTable[i].wins      = 0;
      g_mgTable[i].losses    = 0;
      g_mgTable[i].lastPnl   = 0;
      g_mgTable[i].carry     = 0;
      g_mgTable[i].recTarget = 0;
   }
   g_mgActivationTime = TimeCurrent();
   MG_ClearDealCache();
   MG_InitDealCache();
   if(StringLen(reason) > 0)
      Print("[MG] ", reason, " | activation=", TimeToString(g_mgActivationTime, TIME_DATE|TIME_SECONDS));
}

// Called after a trade closes -- updates streak and mgPnl
void MG_RecordTrade(string sym, double profit)
{
   if(g_mgHistCount < MG_HIST_MAX)
   {
      ArrayResize(g_mgHistSym,    g_mgHistCount + 1);
      ArrayResize(g_mgHistProfit, g_mgHistCount + 1);
      ArrayResize(g_mgHistTime,   g_mgHistCount + 1);
      g_mgHistSym[g_mgHistCount]    = sym;
      g_mgHistProfit[g_mgHistCount] = profit;
      g_mgHistTime[g_mgHistCount]   = TimeCurrent();
      g_mgHistCount++;
   }
   if(g_mgmOpen) TCU_DrawMGMonitor();
}

// Returns true if this deal ticket was already counted in the streak (dedup guard).
bool MG_IsDealProcessed(ulong deal)
{
   if(deal == 0) return true; // treat invalid deal as already processed
   for(int _i = 0; _i < MG_DEAL_CACHE; _i++)
      if(g_mgProcessedDeals[_i] == deal) return true;
   return false;
}

// Mark a deal ticket as processed (circular buffer, oldest entry overwritten).
void MG_MarkDealProcessed(ulong deal)
{
   g_mgProcessedDeals[g_mgProcessedHead % MG_DEAL_CACHE] = deal;
   g_mgProcessedHead++;
}

// Called ONCE from OnInit after streak restore from GlobalVariables.
// Pre-marks every recent closing deal as already-processed so that
// MG_SyncFromHistory (which runs inside CalcLots) will NOT re-count
// them on top of the already-restored streak.  Fixes the critical
// streak-inflation-on-restart bug.
void MG_InitDealCache()
{
   datetime since = MG_HistoryFloor();
   if(!HistorySelect(since, TimeCurrent() + 1)) return;
   int total = HistoryDealsTotal();
   int marked = 0;
   for(int _i = 0; _i < total; _i++)
   {
      ulong tk = HistoryDealGetTicket(_i);
      if(tk == 0) continue;
      long dEntry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(dEntry != DEAL_ENTRY_OUT && dEntry != DEAL_ENTRY_INOUT) continue;
      long dMagic = HistoryDealGetInteger(tk, DEAL_MAGIC);
      if(dMagic != MagicNumber && dMagic != 0 && MagicNumber != 0) continue;
      if(!MG_IsDealProcessed(tk))
      {
         MG_MarkDealProcessed(tk);
         marked++;
      }
   }
   if(marked > 0)
      Print("[MG] InitDealCache: pre-marked ", marked, " recent closing deal(s) to prevent double-count");
}

// Returns true if this closing deal was a PARTIAL close of its position --
// i.e. at least one later closing (OUT/INOUT) deal for the same position ID
// exists in the currently-selected history buffer.  This replaces the old
// PositionSelectByTicket(posId) check, which only tells you whether the
// position is open RIGHT NOW; for positions that were partially closed and
// then fully closed before a restart, that call always returned false and
// caused every historic partial to be counted as a full win/loss.
bool MG_IsHistoricalPartialClose(ulong posId, ulong dealTk)
{
   datetime dealTime = (datetime)HistoryDealGetInteger(dealTk, DEAL_TIME);
   int total = HistoryDealsTotal();
   for(int _j = 0; _j < total; _j++)
   {
      ulong otherTk = HistoryDealGetTicket(_j);
      if(otherTk == 0 || otherTk == dealTk) continue;
      if((ulong)HistoryDealGetInteger(otherTk, DEAL_POSITION_ID) != posId) continue;
      long otherEntry = HistoryDealGetInteger(otherTk, DEAL_ENTRY);
      if(otherEntry != DEAL_ENTRY_OUT && otherEntry != DEAL_ENTRY_INOUT) continue;
      datetime otherTime = (datetime)HistoryDealGetInteger(otherTk, DEAL_TIME);
      if(otherTime > dealTime) return true;
      if(otherTime == dealTime && otherTk > dealTk) return true; // same-ms: larger ticket wins
   }
   return false;
}

// Scan recent deal history for closes on [sym] not yet counted in the streak.
// Fixes the race condition where an opposite-signal close fires AFTER the new
// trade's lot size was already calculated via MG_ApplyLot.
void MG_SyncFromHistory(string sym)
{
   if(!EnableMartingale) return;
   datetime since = MG_HistoryFloor();
   if(!HistorySelect(since, TimeCurrent() + 1)) return;
   int total = HistoryDealsTotal();
   for(int _i = 0; _i < total; _i++)
   {
      ulong tk = HistoryDealGetTicket(_i);
      if(tk == 0 || MG_IsDealProcessed(tk)) continue;
      string dSym = HistoryDealGetString(tk, DEAL_SYMBOL);
      if(dSym != sym) continue;
      long dEntry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(dEntry != DEAL_ENTRY_OUT && dEntry != DEAL_ENTRY_INOUT) continue;
      long dMagic = HistoryDealGetInteger(tk, DEAL_MAGIC);
      if(dMagic != MagicNumber && dMagic != 0 && MagicNumber != 0) continue;
      double dRaw    = HistoryDealGetDouble(tk, DEAL_PROFIT);
      double dProfit = dRaw
                     + HistoryDealGetDouble(tk, DEAL_SWAP)
                     + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      ulong dPosId   = (ulong)HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      bool  dPartial = MG_IsHistoricalPartialClose(dPosId, tk); // [FIX] history-aware partial detection
      MG_MarkDealProcessed(tk); // mark before calling to prevent MG_OnClose re-entry
      MG_OnClose(sym, dProfit, true, dPartial, dRaw);
   }
}

void MG_OnClose(string sym, double profit, bool isMagicMatch, bool isPartial = false, double rawProfit = -999999)
{
   // rawProfit = DEAL_PROFIT only (no commission/swap), used for streak win/loss decision.
   // If not supplied, fall back to full profit (backward compat with MG_SyncFromHistory).
   double streakProfit = (rawProfit > -999998) ? rawProfit : profit;
   bool isLoss = (streakProfit < 0);
   bool isWin  = (streakProfit > 0);
   if(!EnableMartingale || !isMagicMatch) return;
   int idx = MG_GetOrCreate(sym);
   g_mgTable[idx].mgPnl  += profit;   // full profit for P&L tracking
   g_mgTable[idx].lastPnl = profit;
   if(!isPartial) { if(isWin) g_mgTable[idx].wins++; else if(isLoss) g_mgTable[idx].losses++; }
   MG_RecordTrade(sym, profit);

   if(isPartial)
   {
      // Partial close: only accumulate P&L, never update streak.
      // Prevents premature ResetOnWin firing while position is still open.
      Print("[MG] Partial close on ", sym, " profit=", DoubleToString(profit, 2),
            " cumPnl=", DoubleToString(g_mgTable[idx].mgPnl, 2), " (streak unchanged)");
      return;
   }

   if(MartingaleMode == 4)
      g_mgTable[idx].carry = MathMax(0.0, -g_mgTable[idx].mgPnl);

   if(MartingaleMode == 2) // Anti-Martingale: increase on WIN, reset on LOSS
   {
      if(isWin)
      {
         g_mgTable[idx].streak++;
         if(g_mgTable[idx].streak >= MartingaleMaxSteps)
         {
            Print("[MG] Anti-Martin max steps hit on ", sym, " -- reset");
            g_mgTable[idx].streak = 0;
            g_mgTable[idx].mgPnl  = 0;
         }
         else Print("[MG] Anti-Martin WIN streak=", g_mgTable[idx].streak, " on ", sym);
      }
      else if(isLoss)
      {
         Print("[MG] Anti-Martin LOSS on ", sym, " -- streak reset");
         g_mgTable[idx].streak = 0;
         g_mgTable[idx].mgPnl  = 0;
      }
   }
   else // Classic / Custom / FixedStep / Recovery: increase on LOSS
   {
      if(isLoss)
      {
         g_mgTable[idx].streak++;
         if(MartingaleMode == 4)
            g_mgTable[idx].recTarget = 0;
         if(g_mgTable[idx].streak >= MartingaleMaxSteps)
         {
            Print("[MG] Max steps (", MartingaleMaxSteps, ") hit on ", sym, " -- reset");
            g_mgTable[idx].streak    = 0;
            g_mgTable[idx].mgPnl     = 0;
            g_mgTable[idx].carry     = 0;
            g_mgTable[idx].recTarget = 0;
         }
         else Print("[MG] Loss streak=", g_mgTable[idx].streak, " on ", sym,
                    " | cumPnl=", DoubleToString(g_mgTable[idx].mgPnl, 2),
                    (MartingaleMode == 4 ? " | carry=$" + DoubleToString(g_mgTable[idx].carry, 2) : ""));
      }
      else if(isWin && MartingaleMode == 4 && g_mgTable[idx].carry <= 0.0000001)
      {
         Print("[MG] Advanced recovery completed on ", sym, " -- reset | recovered=",
               DoubleToString(g_mgTable[idx].mgPnl, 2));
         g_mgTable[idx].streak    = 0;
         g_mgTable[idx].mgPnl     = 0;
         g_mgTable[idx].carry     = 0;
         g_mgTable[idx].recTarget = 0;
      }
      else if(isWin && MartingaleResetOnWin)
      {
         Print("[MG] WIN on ", sym, " -- reset (ResetOnWin=true) | recovered=",
               DoubleToString(g_mgTable[idx].mgPnl, 2));
         g_mgTable[idx].streak    = 0;
         g_mgTable[idx].mgPnl     = 0;
         g_mgTable[idx].carry     = 0;
         g_mgTable[idx].recTarget = 0;
      }
   }
}

// Apply martingale multiplier to base lot. Returns adjusted lot.
// Recovery mode (4) needs slPrice and dir to calculate dollar-based recovery lot.
double MG_ApplyLot(string sym, double baseLots, double slPrice=0, double tpPrice=0, string dir="BUY")
{
   if(!EnableMartingale) return baseLots;
   // Per-symbol MG base lot wins; falls back to global MartingaleBaseLot, then baseLots
   double _mgSymLot = GetMGPerSymbolBaseLot(sym);
   double mgBase = (_mgSymLot > 0) ? _mgSymLot : (MartingaleBaseLot > 0) ? MartingaleBaseLot : baseLots;
   int streak = MG_GetStreak(sym);
   if(streak <= 0) return mgBase;

   // Max cumulative loss safety cap -- freeze at base lot, do not increase further
   if(MartingaleMaxLoss > 0)
   {
      int _mlIdx = MG_Find(sym);
      // [FIX] Use only the loss portion: positive mgPnl (e.g. anti-martingale winning run)
      // must NOT trigger the loss cap.  MathAbs() was firing on profits too.
      double _cumLoss = (_mlIdx >= 0) ? MathMax(0.0, -g_mgTable[_mlIdx].mgPnl) : 0;
      if(_cumLoss >= MartingaleMaxLoss)
      {
         Print("[MG] MaxLoss cap hit for ", sym, ": $", DoubleToString(_cumLoss, 2),
               " >= $", DoubleToString(MartingaleMaxLoss, 2), " -- lot held at base");
         return mgBase;
      }
   }

   double result = mgBase;
   switch(MartingaleMode)
   {
      case 0: result = mgBase * MathPow(2.0,                   streak); break; // Classic
      case 1: result = mgBase * MathPow(MartingaleMultiplier,  streak); break; // Custom
      case 2: result = mgBase * MathPow(MartingaleMultiplier,  streak); break; // AntiMartin (same math, different trigger)
      case 3: result = mgBase + (MartingaleFixedStep * streak);         break; // FixedStep
      case 4: // Recovery (Advanced): recover the carried loss + this signal's own profit
      {
         int rIdx = MG_Find(sym);
         double carry = (rIdx >= 0) ? g_mgTable[rIdx].carry : 0.0;
         // No outstanding loss -> this is a base trade, use the base lot.
         if(carry <= 0) { result = mgBase; break; }

         double tickVal  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double tickSz   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         bool   isSell   = (dir == "SELL");
         double curPrice = isSell ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
         if(tickVal <= 0 || tickSz <= 0) { result = mgBase; break; }

         // TP distance this recovery is sized against (signal TP, else FallbackTPPips).
         double tpDist = (tpPrice > 0 && curPrice > 0) ? MathAbs(curPrice - tpPrice) : 0;
         if(tpDist <= 0 && FallbackTPPips > 0) tpDist = FallbackTPPips * PipSize(sym);
         if(tpDist <= 0)
         {
            Print("[MG] Recovery: signal has no TP and FallbackTPPips=0 -- using base lot.");
            result = mgBase;
            break;
         }

         // Money made by 1.00 lot if price travels to the TP.
         double moneyPerLot = (tpDist / tickSz) * tickVal;
         if(moneyPerLot <= 0) { result = mgBase; break; }

         // Target if TP hits = recover the carried loss + this signal's normal
         // profit at base lot.  Lot = target / moneyPerLot ( = mgBase + carry/moneyPerLot ).
         double normalProfit   = mgBase * moneyPerLot;
         double recoveryTarget = carry + normalProfit;
         double rawLot         = recoveryTarget / moneyPerLot;

         // Round UP to the broker volume step so a TP hit always fully clears the carry.
         double vstep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
         if(vstep <= 0) vstep = 0.01;
         result = MathCeil(rawLot / vstep - 0.0000001) * vstep;

         // Remember the target so MG_OnClose can roll the ladder if this trade loses.
         if(rIdx >= 0) g_mgTable[rIdx].recTarget = recoveryTarget;

         Print("[MG] Recovery: carry=$", DoubleToString(carry,2),
               " + normalProfit=$", DoubleToString(normalProfit,2),
               " = target=$", DoubleToString(recoveryTarget,2),
               "  rawLot=", DoubleToString(rawLot,4),
               " -> lot=", DoubleToString(result,2));
         break;
      }
   }

   bool capped = false;
   if(result > MaxLotSize)
   {
      Print("[MG] Lot capped MaxLot: ", DoubleToString(result,2), "->", DoubleToString(MaxLotSize,2));
      result = MaxLotSize;
      capped = true;
      // Cap hit = reset streak so lot returns to base, but KEEP mgPnl
      // so recovery can still work and the accumulated loss is not erased.
      int idx = MG_Find(sym);
      if(idx >= 0) { g_mgTable[idx].streak = 0; }
   }

   Print("[MG] ", sym, " mode=", MG_ModeText(), " streak=", streak,
         " base=", DoubleToString(baseLots,2), " final=", DoubleToString(result,2),
         capped ? " [CAPPED+RESET]" : "");
   return result;
}

// Seals all recent closing deals for ONE symbol as already-processed so that
// MG_SyncFromHistory won't re-count them after a manual reset.  Intentionally
// does NOT touch deals from other symbols -- those may still be unsynced after
// a restart and must remain available for their own SyncFromHistory call.
void MG_ReSeedSymbol(string sym)
{
   datetime since = MG_HistoryFloor();
   if(!HistorySelect(since, TimeCurrent() + 1)) return;
   int total = HistoryDealsTotal();
   int marked = 0;
   for(int _i = 0; _i < total; _i++)
   {
      ulong tk = HistoryDealGetTicket(_i);
      if(tk == 0) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != sym) continue;
      long dEntry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(dEntry != DEAL_ENTRY_OUT && dEntry != DEAL_ENTRY_INOUT) continue;
      long dMagic = HistoryDealGetInteger(tk, DEAL_MAGIC);
      if(dMagic != MagicNumber && dMagic != 0 && MagicNumber != 0) continue;
      if(!MG_IsDealProcessed(tk)) { MG_MarkDealProcessed(tk); marked++; }
   }
   if(marked > 0)
      Print("[MG] ReSeedSymbol(", sym, "): sealed ", marked, " deal(s) after manual reset");
}

// Manual reset for a symbol (panel button)
void MG_Reset(string sym)
{
   int idx = MG_Find(sym);
   if(idx >= 0) { g_mgTable[idx].streak = 0; g_mgTable[idx].mgPnl = 0; g_mgTable[idx].wins = 0; g_mgTable[idx].losses = 0; g_mgTable[idx].lastPnl = 0; g_mgTable[idx].carry = 0; g_mgTable[idx].recTarget = 0; }
   // [FIX] Seal only this symbol's deals -- MG_InitDealCache() would have sealed
   // every other symbol's unsynced closes too, corrupting their post-restart replay.
   if(EnableMartingale) MG_ReSeedSymbol(sym);
   Print("[MG] Manual reset: ", sym);
}

void MG_ResetAll()
{
   for(int i = 0; i < g_mgCount; i++) { g_mgTable[i].streak = 0; g_mgTable[i].mgPnl = 0; g_mgTable[i].wins = 0; g_mgTable[i].losses = 0; g_mgTable[i].lastPnl = 0; g_mgTable[i].carry = 0; g_mgTable[i].recTarget = 0; }
   // [FIX] Re-seed deal cache so SyncFromHistory won't re-count historical deals.
   if(EnableMartingale)
   {
      g_mgActivationTime = TimeCurrent();
      MG_ClearDealCache();
      MG_InitDealCache();
   }
   Print("[MG] Full reset all symbols");
}

//+------------------------------------------------------------------+
double CalcLots(string sym, double slPrice, double signalLots=0, string dir="BUY", double tpPrice=0)
{
   double lots = FixedLotSize;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   // [v6.01 FIX] Use BID for SELL, ASK for BUY. Legacy code always used ASK
   // which leaks one spread of distance into slDist. For tight-SL scalping
   // (10-pip SL on 3-pip spread) this is a 30% risk-size error.
   bool isSell = (dir == "SELL");
   double price = isSell ? SymbolInfoDouble(sym, SYMBOL_BID)
                         : SymbolInfoDouble(sym, SYMBOL_ASK);
   double tickVal = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSz = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);

   if(LotMode == LOT_LEGACY_UNUSED)
      LotMode = LOT_FIXED;

   // [v6.01 FIX] Honor signal-specified lots (e.g. "LOTS: 0.5" in the message)
   // when LotMode is FIXED and a positive signalLots is provided. Risk-percent
   // mode intentionally ignores this -- when the user has explicitly chosen
   // risk-based sizing, hardcoded signal lots should not override the risk math.
   // PerSymbolLots and Max-clamps still apply below in the normalization block.
   bool sizingResolved = false;
   if(signalLots > 0 && LotMode == LOT_FIXED)
   {
      Print("[LOT] Using signal-specified lots: ", DoubleToString(signalLots, 2),
            " (FIXED mode + signal override)");
      lots = signalLots;
      sizingResolved = true;
   }

   // [v6.00 NEW][PerSymbolLots] Per-symbol override wins over LotMode if a match is found.
   // Min/max/step normalization and SkipIfLotOverMax / MaxLotSize clamps still apply below.
   double overrideLot = sizingResolved ? 0 : GetPerSymbolLot(sym);
   if(overrideLot > 0)
   {
      Print("[LOT] Per-symbol override for ", sym, ": ", DoubleToString(overrideLot, 2), " (LotMode bypassed)");
      lots = overrideLot;
   }
   else if(!sizingResolved)
   {

   Print("[LOT] Mode: ", TCU_LotModeText(), " | SL Price: ", slPrice, " | Fixed: ", FixedLotSize);
   
   if(LotMode == LOT_FIXED)
   {
      lots = FixedLotSize;
      Print("[LOT] Using FIXED: ", DoubleToString(lots, 2));
   }
   else if(LotMode == LOT_RISK_PERCENT)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt = balance * RiskPercent / 100.0;
      double slDist = 0;
      
      // Calculate SL distance
      if(slPrice > 0)
      {
         slDist = MathAbs(price - slPrice);
         Print("[LOT] SL from signal: ", slPrice, " | Distance: ", slDist);
      }
      else
      {
         // Use default SL points
         slDist = DefaultSLPoints * point;
         Print("[LOT] No SL in signal, using default ", DefaultSLPoints, " points = ", slDist);
      }
      
      if(tickSz > 0 && slDist > 0 && tickVal > 0)
      {
         double ticksRisk = slDist / tickSz;
         lots = riskAmt / (ticksRisk * tickVal);
         Print("[LOT] RISK CALC: Balance=", DoubleToString(balance, 2), 
               " | Risk%=", DoubleToString(RiskPercent, 1), 
               " | RiskAmt=", DoubleToString(riskAmt, 2),
               " | TicksRisk=", DoubleToString(ticksRisk, 2),
               " | Result=", DoubleToString(lots, 4));
      }
      else
      {
         Print("[LOT] WARNING: Could not calculate risk! tickSz=", tickSz, " slDist=", slDist, " tickVal=", tickVal);
         lots = FixedLotSize; // Fallback
      }
   }
   }  // [v6.00 NEW][PerSymbolLots] close of "else" block when no per-symbol override matched
   
   // Normalize lot size
   double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepL = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   
   // Fallback if symbol data not loaded yet (returns 0)
   if(minL <= 0) { minL = 0.01; Print("[LOT] WARNING: VOLUME_MIN=0 for ", sym, ", using 0.01 fallback"); }
   if(maxL <= 0) maxL = 100.0;
   if(stepL <= 0) stepL = 0.01;
   
   lots = MathFloor(lots / stepL + 0.0000001) * stepL;
   if(lots < minL)
   {
      // [v6.x FIX] Risk-% sizing that lands below the broker minimum gets
      // floored UP to minLot -- which means the trade risks MORE than the
      // configured RiskPercent. Warn loudly instead of failing silently.
      if(LotMode == LOT_RISK_PERCENT && overrideLot <= 0 && !sizingResolved)
      {
         Print("[LOT] WARNING: risk-based size ", DoubleToString(lots, 4),
               " is below broker minimum ", DoubleToString(minL, 2),
               " -- using min lot. ACTUAL RISK EXCEEDS RiskPercent (",
               DoubleToString(RiskPercent, 2), "%) on this trade.");
         g_lastError = "Min-lot forced: risk > " + DoubleToString(RiskPercent, 2) + "%";
      }
      lots = minL;
   }
    if(lots > maxL) lots = maxL;
    if(SkipIfLotOverMax && lots > MaxLotSize)
    {
       Print("[LOT] Over user max: ", DoubleToString(lots, 2), " > ", DoubleToString(MaxLotSize, 2), " (skip mode)");
       return lots;
    }
    if(lots > MaxLotSize) lots = MaxLotSize;
    
    // [MARTINGALE] Sync any missed closes before applying the multiplier.
   // Fixes race condition where a position closed by an opposite signal AFTER
   // MG_ApplyLot was already called (OnTradeTransaction fires asynchronously).
   MG_SyncFromHistory(sym);
   // [MARTINGALE] Apply multiplier after all normal sizing
   lots = MG_ApplyLot(sym, lots, slPrice, tpPrice, dir);
    lots = MathFloor(lots / stepL + 0.0000001) * stepL;
    if(lots < minL) lots = minL;
    if(lots > maxL) lots = maxL;
    if(lots > MaxLotSize) lots = MaxLotSize;
   
   Print("[LOT] FINAL: ", DoubleToString(lots, 2), " (min=", minL, " max=", maxL, " cap=", MaxLotSize, ")");
   
   return lots;
}

//+------------------------------------------------------------------+
// COPIER LOT CALCULATOR: Independent lot sizing for EA-to-EA Copier (Slave mode)
// Separate from CalcLots so Telegram signal mode and copier mode are independent
//+------------------------------------------------------------------+
double CalcCopierLots(string sym, double slPrice, double masterLots, string dir="", double masterBalance=0.0)
{
   double lots = masterLots;
    double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
   double price  = (dir == "SELL") ? SymbolInfoDouble(sym, SYMBOL_BID)
                                   : SymbolInfoDouble(sym, SYMBOL_ASK);
   double tickVal = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   
   if(CopierLotMode == COPIER_LOT_COPY_MASTER)
   {
      lots = masterLots;
      Print("[COPIER-LOT] COPY MASTER: ", DoubleToString(lots, 2), " lots");
   }
   else if(CopierLotMode == COPIER_LOT_FIXED)
   {
      lots = CopierFixedLot;
      Print("[COPIER-LOT] FIXED: ", DoubleToString(lots, 2), " lots");
   }
   else if(CopierLotMode == COPIER_LOT_MULTIPLIER)
   {
      lots = masterLots * CopierLotMultiplier;
      Print("[COPIER-LOT] MULTIPLIER: ", DoubleToString(masterLots, 2), " x ", CopierLotMultiplier, " = ", DoubleToString(lots, 2));
   }
   else if(CopierLotMode == COPIER_LOT_RISK_PCT)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt = balance * CopierRiskPercent / 100.0;
      double slDist  = (slPrice > 0) ? MathAbs(price - slPrice) : DefaultSLPoints * point;
      if(tickSz > 0 && slDist > 0 && tickVal > 0)
      {
         double ticksRisk = slDist / tickSz;
         lots = riskAmt / (ticksRisk * tickVal);
         Print("[COPIER-LOT] RISK ", CopierRiskPercent, "% = $", DoubleToString(riskAmt,2), " -> ", DoubleToString(lots,4), " lots");
      }
      else
      {
         Print("[COPIER-LOT] WARNING: Cannot calc risk (tickSz=", tickSz, " slDist=", slDist, ") -- Fixed fallback");
         lots = CopierFixedLot;
      }
   }
   else if(CopierLotMode == COPIER_LOT_BALANCE_PROPORTIONAL)
   {
      if(masterBalance <= 0)
         return 0.0;
      double slaveBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lots = masterLots * (slaveBalance / masterBalance);
      Print("[COPIER-LOT] BALANCE PROPORTIONAL: masterLots=", DoubleToString(masterLots, 4),
            " masterBalance=", DoubleToString(masterBalance, 2),
            " slaveBalance=", DoubleToString(slaveBalance, 2),
            " result=", DoubleToString(lots, 4));
   }
   
   // Normalize to broker volume constraints
   double minL  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);  if(minL  <= 0) minL  = 0.01;
   double maxL  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);  if(maxL  <= 0) maxL  = 100.0;
   double stepL = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP); if(stepL <= 0) stepL = 0.01;
   
   lots = MathFloor(lots / stepL + 0.0000001) * stepL;
   if(lots < minL) lots = minL;
   if(lots > maxL) lots = maxL;
   if(CopierMaxLot > 0 && lots > CopierMaxLot) lots = CopierMaxLot;
   
   Print("[COPIER-LOT] FINAL: ", DoubleToString(lots, 2), " (mode=", EnumToString(CopierLotMode), ")");
   return lots;
}

//+------------------------------------------------------------------+
ulong CalcHash(string data)
{
   ulong hash = 5381;
   int len = StringLen(data);
   for(int i = 0; i < len; i++)
   {
      ushort c = StringGetCharacter(data, i);
      hash = ((hash << 5) + hash) + c;  // hash * 33 + c (djb2)
   }
   return hash;
}

//+------------------------------------------------------------------+
bool IsProcessed(ulong hash)
{
   TCU_PruneProcessedHashes();
   int idx = TCU_FindProcessedHashIndex(hash);
   if(idx < 0) return false;
   datetime seenAt = (ArraySize(g_processedHashTimes) > idx) ? g_processedHashTimes[idx] : 0;
   if(seenAt <= 0) return false;
   return ((TimeCurrent() - seenAt) <= TCU_DuplicateWindowSeconds());
}

//+------------------------------------------------------------------+
void MarkProcessed(ulong hash)
{
   TCU_PruneProcessedHashes();
   datetime nowTs = TimeCurrent();
   int idx = TCU_FindProcessedHashIndex(hash);
   if(idx >= 0)
   {
      if(ArraySize(g_processedHashTimes) <= idx)
         ArrayResize(g_processedHashTimes, idx + 1);
      g_processedHashTimes[idx] = nowTs;
      PersistHashes();
      return;
   }

   int sz = ArraySize(g_processedHashes);

   // Keep only last 100 hashes to prevent memory bloat
   if(sz >= 100)
   {
      for(int i = 0; i < sz - 1; i++)
      {
         g_processedHashes[i] = g_processedHashes[i + 1];
         g_processedHashTimes[i] = g_processedHashTimes[i + 1];
      }
      g_processedHashes[sz - 1] = hash;
      g_processedHashTimes[sz - 1] = nowTs;
   }
   else
   {
      ArrayResize(g_processedHashes, sz + 1);
      ArrayResize(g_processedHashTimes, sz + 1);
      g_processedHashes[sz] = hash;
      g_processedHashTimes[sz] = nowTs;
   }

   PersistHashes();
}

void PersistHashes()
{
   TCU_PruneProcessedHashes();
   int keep = MathMin(ArraySize(g_processedHashes), 100);
   int base = ArraySize(g_processedHashes) - keep;
   int h = FileOpen(HashFile(), FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   for(int i = 0; i < keep; i++)
      FileWriteString(h, HashToLine(g_processedHashes[base + i], g_processedHashTimes[base + i]) + "\r\n");
   FileClose(h);
}

// Load hashes that were persisted before last restart
void LoadPersistedHashes()
{
   if(!FileIsExist(HashFile(), FILE_COMMON)) return;
   int h = FileOpen(HashFile(), FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return;

   int loaded = 0;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) == 0) continue;

      ulong hh = 0;
      datetime seenAt = 0;
      if(ParseHashLine(line, hh, seenAt))
      {
         if(seenAt <= 0) continue;
         if((TimeCurrent() - seenAt) > TCU_DuplicateWindowSeconds()) continue;
         if(TCU_FindProcessedHashIndex(hh) >= 0) continue;
         int sz = ArraySize(g_processedHashes);
         ArrayResize(g_processedHashes, sz + 1);
         ArrayResize(g_processedHashTimes, sz + 1);
         g_processedHashes[sz] = hh;
         g_processedHashTimes[sz] = seenAt;
         loaded++;
      }
   }
   FileClose(h);
   if(loaded > 0) Print("[INIT] Loaded ", loaded, " signal hashes from file (restart-safe dedup active)");
}

//+------------------------------------------------------------------+
void CloseBySymbol(string sym, string src)
{
   Print("[CLOSE] Closing positions for: ", sym, " (source: ", src, ")");
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         if(g_trade.PositionClose(ticket))
         {
            Print("[CLOSE] Closed ticket #", ticket);
            closed++;
         }
         else
            Print("[CLOSE] Failed to close #", ticket, " - ", g_trade.ResultComment());
      }
   }
   if(closed > 0)
      DoAlert(src + ": Closed " + IntegerToString(closed) + " " + sym + " position(s)");
}

//+------------------------------------------------------------------+
// SYMBOL FILTER: Check if a symbol is allowed by whitelist/blacklist
//+------------------------------------------------------------------+
bool IsSymbolAllowed(string sym)
{
   // If both disabled, allow everything
   if(!EnableWhitelist && !EnableBlacklist) return true;
   
   string symUp = sym;
   StringToUpper(symUp);
   
   // Whitelist takes priority if both are enabled
   if(EnableWhitelist)
   {
      if(StringLen(WhitelistSymbols) == 0) return true; // Empty whitelist = allow all
      string wList = WhitelistSymbols;
      StringToUpper(wList);
      StringReplace(wList, " ", ""); // Remove spaces
      string wItems[];
      int wCount = StringSplit(wList, ',', wItems);
      for(int i = 0; i < wCount; i++)
      {
         StringTrimLeft(wItems[i]);
         StringTrimRight(wItems[i]);
         if(StringLen(wItems[i]) > 0 && StringFind(symUp, wItems[i]) >= 0)
            return true;
      }
      Print("[FILTER] Symbol ", sym, " not in whitelist: ", WhitelistSymbols);
      return false;
   }
   
   // Blacklist mode
   if(EnableBlacklist)
   {
      if(StringLen(BlacklistSymbols) == 0) return true; // Empty blacklist = allow all
      string bList = BlacklistSymbols;
      StringToUpper(bList);
      StringReplace(bList, " ", "");
      string bItems[];
      int bCount = StringSplit(bList, ',', bItems);
      for(int i = 0; i < bCount; i++)
      {
         StringTrimLeft(bItems[i]);
         StringTrimRight(bItems[i]);
         if(StringLen(bItems[i]) > 0 && StringFind(symUp, bItems[i]) >= 0)
         {
            Print("[FILTER] Symbol ", sym, " is blacklisted: ", BlacklistSymbols);
            return false;
         }
      }
      return true;
   }
   
   return true;
}

//+------------------------------------------------------------------+
// BREAKEVEN: Move SL to entry price for positions with our magic number
//+------------------------------------------------------------------+
void MoveToBreakeven(string sym, string src)
{
   Print("[BREAKEVEN] Command received. Symbol filter: ", (StringLen(sym) > 0 ? sym : "ALL"), " (source: ", src, ")");
   int moved = 0;
   int skipped = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      string posSym = PositionGetString(POSITION_SYMBOL);
      
      // If symbol specified, only process that symbol
      if(StringLen(sym) > 0 && posSym != sym) continue;
      
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int digits = (int)SymbolInfoInteger(posSym, SYMBOL_DIGITS);
      bool isBuy = (posType == POSITION_TYPE_BUY);
       
      double newSL = BreakevenSLPrice(posSym, isBuy, entryPrice, BreakevenBufferPips);
      
      // Only move if position is in profit (avoid locking in loss)
      double currentPrice = 0;
      if(posType == POSITION_TYPE_BUY)
         currentPrice = SymbolInfoDouble(posSym, SYMBOL_BID);
      else
         currentPrice = SymbolInfoDouble(posSym, SYMBOL_ASK);
      
      bool inProfit = false;
      if(posType == POSITION_TYPE_BUY && currentPrice > entryPrice) inProfit = true;
      if(posType == POSITION_TYPE_SELL && currentPrice < entryPrice) inProfit = true;
      
      if(!inProfit)
      {
         Print("[BREAKEVEN] Skipping #", ticket, " ", posSym, " - not in profit");
         skipped++;
         continue;
      }
      if((isBuy && currentPrice <= newSL) || (!isBuy && currentPrice >= newSL))
      {
         Print("[BREAKEVEN] Skipping #", ticket, " ", posSym, " - not enough profit for BE buffer (", BreakevenBufferPips, " pips)");
         skipped++;
         continue;
      }
      
      // Check if SL is already at or beyond breakeven
      if(posType == POSITION_TYPE_BUY && currentSL >= newSL)
      {
         Print("[BREAKEVEN] #", ticket, " SL already at/beyond breakeven");
         continue;
      }
      if(posType == POSITION_TYPE_SELL && currentSL > 0 && currentSL <= newSL)
      {
         Print("[BREAKEVEN] #", ticket, " SL already at/beyond breakeven");
         continue;
      }
      
      if(g_trade.PositionModify(ticket, newSL, currentTP))
      {
         Print("[BREAKEVEN] Moved #", ticket, " ", posSym, " SL to breakeven: ", DoubleToString(newSL, digits));
         moved++;
      }
      else
         Print("[BREAKEVEN] Failed #", ticket, " - ", g_trade.ResultComment());
   }
   
   Print("[BREAKEVEN] Done: ", moved, " moved, ", skipped, " skipped (not in profit)");
   if(moved > 0)
      DoAlert(src + ": Breakeven applied to " + IntegerToString(moved) + " position(s)");
}

// Ticket-aware wrapper: when tickets are provided only those positions are processed.
void MoveToBreakevenFiltered(string sym, string src, ulong &tickets[], int ticketCount)
{
   if(ticketCount == 0) { MoveToBreakeven(sym, src); return; }
   Print("[BREAKEVEN] Filtered: ", ticketCount, " ticket(s), sym=", (StringLen(sym)>0?sym:"ALL"), " src=", src);
   int moved = 0, skipped = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!TicketInList(ticket, tickets, ticketCount)) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      string posSym = PositionGetString(POSITION_SYMBOL);
      if(StringLen(sym) > 0 && posSym != sym) continue;
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL  = PositionGetDouble(POSITION_SL);
      double currentTP  = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int digits = (int)SymbolInfoInteger(posSym, SYMBOL_DIGITS);
      bool isBuy = (posType == POSITION_TYPE_BUY);
      double newSL = BreakevenSLPrice(posSym, isBuy, entryPrice, BreakevenBufferPips);
      double curPrice = isBuy ? SymbolInfoDouble(posSym, SYMBOL_BID) : SymbolInfoDouble(posSym, SYMBOL_ASK);
      bool inProfit = isBuy ? (curPrice > entryPrice) : (curPrice < entryPrice);
      if(!inProfit) { Print("[BREAKEVEN] Skip #", ticket, " not in profit"); skipped++; continue; }
      if((isBuy && currentSL >= newSL) || (!isBuy && currentSL > 0 && currentSL <= newSL))
         { Print("[BREAKEVEN] Skip #", ticket, " SL already at/beyond BE"); continue; }
      if(g_trade.PositionModify(ticket, newSL, currentTP))
         { Print("[BREAKEVEN] Moved #", ticket, " ", posSym, " -> BE ", DoubleToString(newSL, digits)); moved++; }
      else
         Print("[BREAKEVEN] Failed #", ticket, " - ", g_trade.ResultComment());
   }
   Print("[BREAKEVEN] Done: ", moved, " moved, ", skipped, " skipped");
   if(moved > 0) DoAlert(src + ": Breakeven applied to " + IntegerToString(moved) + " position(s)");
}

//+------------------------------------------------------------------+
// TRAILING STOP: Manage trailing stop for all positions with our magic
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!EnableTrailingStop) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      string posSym = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double point = SymbolInfoDouble(posSym, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(posSym, SYMBOL_DIGITS);
      
      // Pip size: 10 points for 4/5-digit symbols, 1 point for 2/3-digit
      double pipSize = PipSize(posSym);
      
      double trailStartDist = TrailStartPips * pipSize;
      double trailDist = TrailDistancePips * pipSize;
      double trailStep = TrailStepPips * pipSize;
      
      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(posSym, SYMBOL_BID);
         double profit = bid - entryPrice;
         
         // Only trail if profit exceeds activation threshold
         if(profit < trailStartDist) continue;
         
         double newSL = NormalizeDouble(bid - trailDist, digits);
         
          // Check if we should move to breakeven first
          double beSL = BreakevenSLPrice(posSym, true, entryPrice, BreakevenBufferPips);
          if(TrailMoveToBreakeven && (currentSL < beSL || currentSL == 0))
          {
             // Floor trailing SL at breakeven -- never trail below BE once activated
             if(newSL < beSL)
                newSL = beSL;
          }
         
         // Only move if new SL is higher than current SL and moved by at least TrailStep
         if(newSL > currentSL + trailStep || currentSL == 0)
         {
            if(g_trade.PositionModify(ticket, newSL, currentTP))
               Print("[TRAIL] BUY #", ticket, " ", posSym, " SL: ", DoubleToString(currentSL, digits), " -> ", DoubleToString(newSL, digits));
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(posSym, SYMBOL_ASK);
         double profit = entryPrice - ask;
         
         // Only trail if profit exceeds activation threshold
         if(profit < trailStartDist) continue;
         
         double newSL = NormalizeDouble(ask + trailDist, digits);
         
          // Check if we should move to breakeven first
          double beSL = BreakevenSLPrice(posSym, false, entryPrice, BreakevenBufferPips);
          if(TrailMoveToBreakeven && (currentSL > beSL || currentSL == 0))
          {
             // Cap trailing SL at breakeven -- never trail above BE once activated
             if(newSL > beSL)
                newSL = beSL;
          }
         
         // Only move if new SL is lower than current SL (or no SL set) and moved by at least TrailStep
         if(currentSL == 0 || newSL < currentSL - trailStep)
         {
            if(g_trade.PositionModify(ticket, newSL, currentTP))
               Print("[TRAIL] SELL #", ticket, " ", posSym, " SL: ", DoubleToString(currentSL, digits), " -> ", DoubleToString(newSL, digits));
         }
      }
   }
}


//+------------------------------------------------------------------+
void UpdateModeStr()
{
   g_currentMode = "";
   if(EnableBridgeMode) g_currentMode += "Bridge ";
   if(EnableBotAPIMode) g_currentMode += "BotAPI ";
   if(EnableDiscordMode) g_currentMode += "DiscordSend ";
   if(EnableTelegramSend) g_currentMode += "Sender ";
   if(CopierMode == MODE_MASTER) g_currentMode += "Master ";
   if(CopierMode == MODE_SLAVE) g_currentMode += "Slave ";
   if(StringLen(g_currentMode) == 0) g_currentMode = "Standby";
   StringTrimRight(g_currentMode);
}

//+------------------------------------------------------------------+
void DoAlert(string msg)
{
   if(EnablePopupAlerts) Alert(msg);
   if(EnableSoundAlerts) PlaySound(AlertSoundFile);
   if(EnablePushNotify) SendNotification(msg);
   if(EnableDiscordMode && StringLen(DiscordWebhookURL) > 10 &&
      g_dcSenderStartTime > 0 && TimeCurrent() > g_dcSenderStartTime)
   {
      ArrayResize(g_dcQueue, g_dcQueueSize + 1);
      ArrayResize(g_dcQueueRetries, g_dcQueueSize + 1);
      g_dcQueue[g_dcQueueSize] = msg;
      g_dcQueueRetries[g_dcQueueSize] = 0;
      g_dcQueueSize++;
   }
}

//+------------------------------------------------------------------+
void SeedSentAlertTickets()
{
   ArrayResize(g_sentAlertTickets, 0);
   int posTotal = PositionsTotal();
   int keep = 0;
   for(int i = posTotal - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(keep >= 500) break;
      ArrayResize(g_sentAlertTickets, keep + 1);
      g_sentAlertTickets[keep++] = ticket;
   }
   Print("[SEND] Seeded ", keep, " existing position ticket(s) so sender mode only broadcasts NEW trades.");
}

//+------------------------------------------------------------------+
void ArmTelegramSenderFresh()
{
   g_tgSenderStartTime = TimeCurrent();
   ClearTelegramSendQueue();
   SeedSentAlertTickets();
}

//+------------------------------------------------------------------+
void ArmDiscordSenderFresh()
{
   g_dcSenderStartTime = TimeCurrent();
   ClearDiscordSendQueue();
   SeedSentAlertTickets();
}

//+------------------------------------------------------------------+
void ClearTelegramSendQueue()
{
   ArrayResize(g_tgQueue, 0);
   ArrayResize(g_tgQueueRetries, 0);
   g_tgQueueSize = 0;
}

//+------------------------------------------------------------------+
void ClearDiscordSendQueue()
{
   ArrayResize(g_dcQueue, 0);
   ArrayResize(g_dcQueueRetries, 0);
   g_dcQueueSize = 0;
}

//+------------------------------------------------------------------+
// Queue-based version: no WebRequest blocking from OnTick
void QueueNewTrades()
{
   int posTotal = PositionsTotal();
   for(int i = posTotal - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      
      bool found = false;
      int sentSz = ArraySize(g_sentAlertTickets);
      for(int j = 0; j < sentSz; j++)
         if(g_sentAlertTickets[j] == ticket) { found = true; break; }
      if(found) continue;
      
      string sym = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double lots = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      
      string typeStr = "BUY";
      if(ptype == POSITION_TYPE_SELL) typeStr = "SELL";
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      
      string tag = (StringLen(TelegramSendTag) > 0) ? TelegramSendTag + " " : "";
      // Embed hidden machine marker so anti-loop filter catches this regardless of tag changes
      // Fixed permanent anti-loop marker -- hardcoded, never changes, never visible in UI
      string msg = "|NTS-BCT|" + tag + typeStr + " " + sym + " Entry: " + DoubleToString(entry, digits);
      if(sl > 0) msg += " SL: " + DoubleToString(sl, digits);
      if(tp > 0) msg += " TP: " + DoubleToString(tp, digits);
      msg += " Lots: " + DoubleToString(lots, 2);
      if(StringLen(TelegramSendSuffix) > 0) msg += " " + TelegramSendSuffix;
      
      // Queue instead of blocking send -- drained 1-at-a-time from OnTimer
      bool queueTelegram = EnableTelegramSend && g_tgSenderStartTime > 0 && openTime > g_tgSenderStartTime;
      bool queueDiscord = EnableDiscordMode && StringLen(DiscordWebhookURL) > 10 &&
                          g_dcSenderStartTime > 0 && openTime > g_dcSenderStartTime;
      if(queueTelegram)
      {
         ArrayResize(g_tgQueue, g_tgQueueSize + 1);
         ArrayResize(g_tgQueueRetries, g_tgQueueSize + 1);
         g_tgQueue[g_tgQueueSize] = msg;
         g_tgQueueRetries[g_tgQueueSize] = 0;
         g_tgQueueSize++;
      }
      if(queueDiscord)
      {
         ArrayResize(g_dcQueue, g_dcQueueSize + 1);
         ArrayResize(g_dcQueueRetries, g_dcQueueSize + 1);
         g_dcQueue[g_dcQueueSize] = msg;
         g_dcQueueRetries[g_dcQueueSize] = 0;
         g_dcQueueSize++;
      }
      
      if(sentSz >= 500)
      {
         for(int k = 0; k < sentSz - 1; k++)
            g_sentAlertTickets[k] = g_sentAlertTickets[k + 1];
         sentSz = 499;
         ArrayResize(g_sentAlertTickets, sentSz);
      }
      ArrayResize(g_sentAlertTickets, sentSz + 1);
      g_sentAlertTickets[sentSz] = ticket;
      g_tradesSent++;
   }
}

//+------------------------------------------------------------------+
bool SendTgMsg(string msg)
{
   // Determine which bot token and chat ID to use for sending
   string useToken = TelegramBotToken;
   string useChat  = TelegramChatID;
   
   if(UseSeparateSendBot && StringLen(SendBotToken) > 10 && StringLen(SendChatID) > 0)
   {
      useToken = SendBotToken;
      useChat  = SendChatID;
   }
   
   if(StringLen(useToken) == 0 || StringLen(useChat) == 0)
   {
      Print("[TG] ERROR: Missing BotToken or ChatID");
      return false;
   }

   string url = TELEGRAM_URL + useToken + "/sendMessage";
   string body = "chat_id=" + UrlEncode(useChat) + "&text=" + UrlEncode(msg);
   char post[];
   StringToCharArray(body, post, 0, StringLen(body));
   if(ArraySize(post) > 0 && post[ArraySize(post) - 1] == 0)
      ArrayResize(post, ArraySize(post) - 1);
   char result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string resultHeaders = "";
   ResetLastError();
   int res = WebRequest("POST", url, headers, 2000, post, result, resultHeaders);

   if(res == 200)
   {
      Print("[TG] Message sent");
      return true;
   }

   int err = GetLastError();
   string errorMsg = (res == -1 && err == 4060)
      ? "WebRequest blocked - add https://api.telegram.org"
      : (res == -1 ? "WebRequest err " + IntegerToString(err)
                   : "HTTP " + IntegerToString(res));
   Print("[TG] ERROR: ", errorMsg);
   g_lastError = "Telegram send failed: " + errorMsg;
   return false;
}

bool SendDiscordMsg(string msg)
{
   if(StringLen(DiscordWebhookURL) < 10)
   {
      Print("[DISCORD] ERROR: Missing webhook URL");
      return false;
   }

   string body = "{\"content\":\"" + JsonEscape(msg) + "\"}";
   char post[];
   StringToCharArray(body, post, 0, StringLen(body));
   if(ArraySize(post) > 0 && post[ArraySize(post) - 1] == 0)
      ArrayResize(post, ArraySize(post) - 1);
   char result[];
   string headers = "Content-Type: application/json\r\n";
   string resultHeaders = "";
   ResetLastError();
   int res = WebRequest("POST", DiscordWebhookURL, headers, 2000, post, result, resultHeaders);

   if(res == 200 || res == 204)
   {
      Print("[DISCORD] Message sent");
      return true;
   }

   int err = GetLastError();
   string errorMsg = (res == -1 && err == 4060)
      ? "WebRequest blocked - add Discord webhook URL"
      : (res == -1 ? "WebRequest err " + IntegerToString(err)
                   : "HTTP " + IntegerToString(res));
   Print("[DISCORD] ERROR: ", errorMsg);
   g_lastError = "Discord send failed: " + errorMsg;
   return false;
}

void WriteMasterTrades()
{
   if(g_writeInProgress) return;
   g_writeInProgress = true;

   int posTotal = PositionsTotal();
   
   // Periodic diagnostic: log position count every 30s or on change
   static ulong lastDiag = 0;
   static int lastDiagCount = -1;
   ulong nowDiag = GetTickCount64();
   if(posTotal != lastDiagCount || nowDiag - lastDiag >= 30000)
   {
      Print("[MASTER] PositionsTotal()=", posTotal, " Connected=", TerminalInfoInteger(TERMINAL_CONNECTED));
      lastDiag = nowDiag;
      lastDiagCount = posTotal;
   }
   
   // Only skip if terminal is genuinely not connected AND no positions
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) && posTotal == 0)
   {
      static ulong lastSyncLog = 0;
      ulong nowS = GetTickCount64();
      if(nowS - lastSyncLog >= 10000)
      {
         Print("[MASTER] Terminal not connected and no positions -- skipping write");
         lastSyncLog = nowS;
      }
      g_writeInProgress = false;
      return;
   }
   
   if(posTotal > 0) g_masterSynced = true;
   
   // Write file -- always write current state (even 0 positions after sync)
   // This allows slave to detect master closed all trades
   int handle = FileOpen(CopierFileName, FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   if(handle == INVALID_HANDLE)
   {
      // Retry once
      Sleep(FILE_RETRY_TIMEOUT);
      handle = FileOpen(CopierFileName, FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   }
   if(handle == INVALID_HANDLE)
   {
      static ulong lastErrLog = 0;
      ulong nowE = GetTickCount64();
      if(nowE - lastErrLog >= 10000)
      {
         Print("[MASTER] ERROR: Could not open file: ", CopierFileName);
         lastErrLog = nowE;
      }
      g_writeInProgress = false;
      return;
   }
   
   TCU_WriteMasterMeta();
   FileWrite(handle, "Ticket", "Symbol", "Type", "Lots", "Price", "SL", "TP", "Time");
   
   int written = 0;
   string debugTickets = "";
   ulong nowWrite = GetTickCount64();
   bool baselineWarmup = (CopierStartupCopyMode == COPY_NEW_TRADES_ONLY &&
                          g_masterActivationTime > 0 &&
                          g_masterActivationBaselineUntil > 0 &&
                          nowWrite < g_masterActivationBaselineUntil);
   if(g_masterActivationBaselineUntil > 0 && nowWrite >= g_masterActivationBaselineUntil)
      g_masterActivationBaselineUntil = 0;
   
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      
      string sym = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double lots = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      
      string typeStr = "BUY";
      if(ptype == POSITION_TYPE_SELL) typeStr = "SELL";
      if(baselineWarmup && openTime <= g_masterActivationTime)
         typeStr = "BASE_" + typeStr;
      
      FileWrite(handle, ticket, sym, typeStr, lots, price, sl, tp, openTime);
      written++;
      debugTickets += "#" + IntegerToString((long)ticket) + "(" + sym + ") ";
   }
   
   FileClose(handle);
   
   // Log only when position count changes or every 30s
   static ulong lastWriteLog = 0;
   static int lastWritten = -1;
   ulong nowW = GetTickCount64();
   if(written != lastWritten)
   {
      Print("[MASTER] Positions changed: ", lastWritten, " -> ", written, " | ", debugTickets);
      if(written > lastWritten && lastWritten >= 0)
         WriteReport("MASTER_OPEN", "", "", 0, 0, 0, "positions: "+IntegerToString(lastWritten)+" -> "+IntegerToString(written));
      else if(written < lastWritten && lastWritten >= 0)
         WriteReport("MASTER_CLOSE", "", "", 0, 0, 0, "positions: "+IntegerToString(lastWritten)+" -> "+IntegerToString(written));
      lastWriteLog = nowW;
      lastWritten = written;
   }
   else if(nowW - lastWriteLog >= 30000)
   {
      Print("[MASTER] ", written, " position(s): ", debugTickets);
      lastWriteLog = nowW;
   }

   g_writeInProgress = false;
}
void ScanCopierFile()
{
   // Re-entrancy guard
   if(g_scanInProgress) return;
   g_scanInProgress = true;

   int handle = FileOpen(CopierFileName, FILE_READ|FILE_CSV|FILE_COMMON|FILE_SHARE_WRITE|FILE_SHARE_READ, ',');
   if(handle == INVALID_HANDLE)
   {
      // Retry once
      Sleep(FILE_RETRY_TIMEOUT);
      handle = FileOpen(CopierFileName, FILE_READ|FILE_CSV|FILE_COMMON|FILE_SHARE_WRITE|FILE_SHARE_READ, ',');
   }
   if(handle == INVALID_HANDLE)
   {
      static ulong lastNoFile = 0;
      ulong now2 = GetTickCount64();
      if(now2 - lastNoFile >= 10000)
      {
         string commonPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
         Print("[SLAVE] Waiting for Master file: ", CopierFileName, " in ", commonPath, "\\Files\\");
         lastNoFile = now2;
      }
      g_scanInProgress = false;
      return;
   }
   
   // Read CSV header and reject half-written/truncated files. This lets us
   // close quickly on a real header-only file while ignoring write races.
   int csvCols = 0;
   while(!FileIsEnding(handle))
   {
      FileReadString(handle);
      csvCols++;
      if(FileIsLineEnding(handle)) break;
   }
   if(csvCols < 8)
   {
      if(EnableDiagLog)
         Print("[SLAVE] Invalid/partial CSV header in ", CopierFileName, ": columns=", csvCols);
      FileClose(handle);
      g_scanInProgress = false;
      return;
   }
   
   // Debug: log scan state periodically
   static ulong lastScanDebug = 0;
   ulong nowDbg = GetTickCount64();
   if(EnableDiagLog && nowDbg - lastScanDebug >= 5000) // Every 5 seconds
   {
      Print("[SLAVE-DBG] Scan: syncDone=", g_initialSyncDone, 
            " copiedTickets=", ArraySize(g_copiedTickets),
            " masterMap=", ArraySize(g_masterTicketMap),
            " filePos=", FileTell(handle));
      lastScanDebug = nowDbg;
   }
   
   // Collect all master tickets currently in file
   ulong fileTickets[];
   int fileTicketCount = 0;
   ulong initialSyncSnapshotHash = 1469598103934665603;
   double masterBalanceMeta = TCU_ReadMasterBalanceMeta();
   
   while(!FileIsEnding(handle))
   {
      string ticketStr = FileReadString(handle);
      if(StringLen(ticketStr) == 0) break;
      
      ulong masterTicket = (ulong)StringToInteger(ticketStr);
      string sym = FileReadString(handle);
      string typeStr = FileReadString(handle);
      double masterLots = StringToDouble(FileReadString(handle));
      double masterEntry = StringToDouble(FileReadString(handle));
      double sl = StringToDouble(FileReadString(handle));
      double tp = StringToDouble(FileReadString(handle));
      string timeStr = FileReadString(handle);
      double masterBalance = masterBalanceMeta;
      if(csvCols >= 9)
         masterBalance = StringToDouble(FileReadString(handle));
      for(int extraCol = 9; extraCol < csvCols; extraCol++)
         FileReadString(handle);
      datetime openTime = StringToTime(timeStr);
      bool masterBaselineRow = false;
      if(typeStr == "BASE_BUY")  { masterBaselineRow = true; typeStr = "BUY";  }
      if(typeStr == "BASE_SELL") { masterBaselineRow = true; typeStr = "SELL"; }
      
      // CSV data validation: skip corrupt/invalid rows
      if(masterTicket == 0 || StringLen(sym) < 3 || (typeStr != "BUY" && typeStr != "SELL") || masterLots <= 0)
      {
         Print("[SLAVE] Skipping invalid CSV row: ticket=", masterTicket, " sym=", sym, " type=", typeStr, " lots=", masterLots);
         continue;
      }
      
      // Track this master ticket
      ArrayResize(fileTickets, fileTicketCount + 1);
      fileTickets[fileTicketCount] = masterTicket;
      fileTicketCount++;
      initialSyncSnapshotHash ^= (ulong)masterTicket;
      initialSyncSnapshotHash *= 1099511628211;
      
      if(!CopySL) sl = 0;
      if(!CopyTP) tp = 0;
      
      // Check if already copied
      bool found = false;
      int copiedSz = ArraySize(g_copiedTickets);
      for(int j = 0; j < copiedSz; j++)
         if(g_copiedTickets[j] == masterTicket) { found = true; break; }

      if(masterBaselineRow && CopierStartupCopyMode == COPY_NEW_TRADES_ONLY)
      {
         if(!found)
            TCU_RegisterSlaveBaselineTrade(masterTicket, typeStr, sym, masterLots, "MASTER_BASELINE", "Master warmup baseline");
         continue;
      }
      
      if(found)
      {
         bool mapMatched = false;
         int mapSzPC = ArraySize(g_masterTicketMap);
         for(int p = 0; p < mapSzPC; p++)
         {
            if(g_masterTicketMap[p] == masterTicket)
            {
               mapMatched = true;
               if(p >= ArraySize(g_slaveTickets)) break;
               ulong slvTkt = g_slaveTickets[p];
               if(!PositionSelectByTicket(slvTkt))
               {
                  if(TCU_RestoreSlaveMapForMaster(masterTicket, sym, typeStr, masterLots))
                  {
                     slvTkt = g_slaveTickets[p];
                  }
                  if(!PositionSelectByTicket(slvTkt)) break;
               }
               
               string slaveSym = PositionGetString(POSITION_SYMBOL);
               int digits = (int)SymbolInfoInteger(slaveSym, SYMBOL_DIGITS);
               
               // SL/TP SYNC: Compare master SL/TP with slave and update if changed
               if(CopySL || CopyTP)
               {
                  double curSL = PositionGetDouble(POSITION_SL);
                  double curTP = PositionGetDouble(POSITION_TP);
                  double syncSL = sl;
                  double syncTP = tp;
                  if(ReverseSignal)
                  {
                     double slvEntry = PositionGetDouble(POSITION_PRICE_OPEN);
                     if(syncSL > 0) syncSL = slvEntry + (masterEntry - syncSL);
                     if(syncTP > 0) syncTP = slvEntry + (masterEntry - syncTP);
                  }
                  double newSL = (CopySL && syncSL > 0) ? NormalizeDouble(syncSL, digits) : curSL;
                  double newTP = (CopyTP && syncTP > 0) ? NormalizeDouble(syncTP, digits) : curTP;
                  // Also sync removal: if master removed SL/TP, remove from slave
                  if(CopySL && sl == 0) newSL = 0;
                  if(CopyTP && tp == 0) newTP = 0;

                  ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                  double curBid = SymbolInfoDouble(slaveSym, SYMBOL_BID);
                  double curAsk = SymbolInfoDouble(slaveSym, SYMBOL_ASK);
                  if(newSL > 0)
                  {
                     bool badSL = (posType == POSITION_TYPE_BUY && curBid > 0 && newSL >= curBid) ||
                                  (posType == POSITION_TYPE_SELL && curAsk > 0 && newSL <= curAsk);
                     if(badSL)
                     {
                        Print("[SLAVE] Skipping invalid synced SL for #", slvTkt, " after reverse handling: ", newSL);
                        newSL = curSL;
                     }
                  }
                  if(newTP > 0)
                  {
                     bool badTP = (posType == POSITION_TYPE_BUY && curAsk > 0 && newTP <= curAsk) ||
                                  (posType == POSITION_TYPE_SELL && curBid > 0 && newTP >= curBid);
                     if(badTP)
                     {
                        Print("[SLAVE] Skipping invalid synced TP for #", slvTkt, " after reverse handling: ", newTP);
                        newTP = curTP;
                     }
                  }
                  
                  if(MathAbs(newSL - curSL) > SymbolInfoDouble(slaveSym, SYMBOL_POINT) ||
                     MathAbs(newTP - curTP) > SymbolInfoDouble(slaveSym, SYMBOL_POINT))
                  {
                     if(g_trade.PositionModify(slvTkt, newSL, newTP))
                        Print("[SLAVE] SL/TP synced for #", slvTkt, " SL:", curSL, "->", newSL, " TP:", curTP, "->", newTP);
                     else
                        Print("[SLAVE] SL/TP modify FAILED for #", slvTkt, " - ", g_trade.ResultComment());
                  }
               }
               
               // Check for partial close — master lot size decreased
               if(CopierAutoClose && p < ArraySize(g_masterLots))
               {
                  if(g_masterLots[p] > 0.0001 && masterLots < g_masterLots[p] - 0.0001)
                  {
                     double slaveLots = PositionGetDouble(POSITION_VOLUME);
                     double ratio = masterLots / g_masterLots[p];
                     double newSlaveLots = NormalizeDouble(slaveLots * ratio, 2);
                     double closeLots = slaveLots - newSlaveLots;
                     double stepL = SymbolInfoDouble(slaveSym, SYMBOL_VOLUME_STEP);
                     if(stepL > 0) closeLots = MathFloor(closeLots / stepL) * stepL;
                     double minL = SymbolInfoDouble(slaveSym, SYMBOL_VOLUME_MIN);
                     if(closeLots >= minL)
                     {
                        Print("[SLAVE] Partial close: master #", masterTicket, " lots ", g_masterLots[p], " -> ", masterLots, " closing ", closeLots, " from slave #", slvTkt);
                        if(!g_trade.PositionClosePartial(slvTkt, closeLots))
                        {
                           Print("[SLAVE] Partial close FAILED for #", slvTkt, " - ", g_trade.ResultComment());
                           WriteReport("PARTIAL_CLOSE_FAIL", slaveSym, "", closeLots, masterTicket, slvTkt, g_trade.ResultComment());
                        }
                        else
                        {
                           Print("[SLAVE] Partial close OK for #", slvTkt);
                           WriteReport("PARTIAL_CLOSE", slaveSym, "", closeLots, masterTicket, slvTkt, DoubleToString(g_masterLots[p],2)+" -> "+DoubleToString(masterLots,2));
                           g_masterLots[p] = masterLots;
                           SaveSlaveState();
                        }
                     }
                  }
               }
               break;
            }
         }
         if(!mapMatched)
         {
            if(!TCU_RestoreSlaveMapForMaster(masterTicket, sym, typeStr, masterLots))
               Print("[SLAVE] Ticket #", masterTicket, " is in copiedTickets but has no active master/slave map entry and no live slave position could be re-linked.");
         }
         continue;
      }
      
      // Map symbol and ensure it's in MarketWatch
      sym = MapSym(sym);
      if(!SymbolInfoInteger(sym, SYMBOL_VISIBLE))
      {
         Print("[SLAVE] Adding ", sym, " to MarketWatch");
         SymbolSelect(sym, true);
         // Market point load check removed to comply with non-blocking rules
      }

      ulong nowGuard = GetTickCount64();
      if(CopierStartupCopyMode == COPY_NEW_TRADES_ONLY &&
         g_slaveActivationGuardUntil > 0 &&
         nowGuard < g_slaveActivationGuardUntil)
      {
         TCU_RegisterSlaveBaselineTrade(masterTicket, typeStr, sym, masterLots, "SLAVE_GUARD", "Activation guard: registering existing trade");
         continue;
      }
      if(g_slaveActivationGuardUntil > 0 && nowGuard >= g_slaveActivationGuardUntil)
         g_slaveActivationGuardUntil = 0;
      
      // INITIAL SYNC: On the FIRST scan, register ALL existing CSV trades as
      // "already known" without copying ANY of them. This is the ONLY reliable
      // way to prevent copying old/stale trades. The time filter approach fails
      // because master and slave can be on different brokers with different clocks.
      // Only trades that appear NEW in SUBSEQUENT scans will be copied.
      if(!g_initialSyncDone)
      {
         TCU_RegisterSlaveBaselineTrade(masterTicket, typeStr, sym, masterLots, "INITIAL_SYNC", "Initial sync: registering existing trade");
         continue;
      }
      
      // NEW TRADE FOUND
      Print("[SLAVE] *** NEW trade #", masterTicket, ": ", typeStr, " ", sym, " ", masterLots, 
            " lots | copiedArr=", copiedSz, " | syncDone=", g_initialSyncDone);

      if(CopierMinimumLotToCopy > 0 && masterLots + 0.0000001 < CopierMinimumLotToCopy)
      {
         static ulong lastMinLotSkipLog = 0;
         ulong nowMinLot = GetTickCount64();
         if(nowMinLot - lastMinLotSkipLog >= 10000)
         {
            Print("[SLAVE] Master lot below copy threshold for #", masterTicket, ": ",
                  DoubleToString(masterLots, 2), " < ", DoubleToString(CopierMinimumLotToCopy, 2),
                  " - waiting");
            lastMinLotSkipLog = nowMinLot;
         }
         continue;
      }

      if(!ArmExecution)
      {
         g_lastFilterReason = "DISARMED";
         Print("[SLAVE] DISARMED -- master #", masterTicket, " detected but NOT copied. Will retry when ARMED.");
         WriteReport("DISARMED_SKIP", sym, typeStr, masterLots, masterTicket, 0, "slave copy blocked by ArmExecution=false");
         continue; // Don't mark copied; copy can happen later if user arms the EA.
      }

      // Max open positions safety cap
      // [v6.01 FIX] Count BOTH live positions AND unfilled pendings (parity
      // with the signal path). A slave account with manual pendings stacked
      // up should still respect the cap.
      int effectiveSlaveMaxOpen = TCU_EffectiveMaxOpenPositions();
      int slaveActiveCount = PositionsTotal() + OrdersTotal();
      if(effectiveSlaveMaxOpen > 0 && slaveActiveCount >= effectiveSlaveMaxOpen)
      {
         Print("[SLAVE] Max open positions reached (positions=", PositionsTotal(), " pendings=", OrdersTotal(), " cap=", effectiveSlaveMaxOpen, "). Skipping master #", masterTicket);
         continue; // Don't add to copiedTickets — will retry when a position is closed
      }
      
      // Calculate lots using CopierLotMode (independent of Telegram signal LotMode)
      double lots = CalcCopierLots(sym, sl, masterLots, typeStr, masterBalance);
      if(lots <= 0)
      {
         static ulong lastCopierLotCalcFailLog = 0;
         ulong nowCopierLotCalcFail = GetTickCount64();
         if(nowCopierLotCalcFail - lastCopierLotCalcFailLog >= 10000)
         {
            Print("[SLAVE] Copier lot calculation failed for master #", masterTicket, " - waiting");
            WriteReport("LOT_CALC_FAIL", sym, typeStr, 0, masterTicket, 0, "copier lot calculation failed");
            lastCopierLotCalcFailLog = nowCopierLotCalcFail;
         }
         continue;
      }
      lots = MathMin(lots, CopierMaxLot);
      
      // Normalize to broker's volume constraints
      double stepL = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      if(stepL > 0) lots = MathRound(lots / stepL) * stepL;
      if(minL > 0 && lots < minL) lots = minL;
      if(maxL > 0 && lots > maxL) lots = maxL;
      
      // Check spread (only if filter enabled)
      int spread = (int)SymbolInfoInteger(sym, SYMBOL_SPREAD);
      int effectiveSlaveMaxSpread = TCU_EffectiveMaxSpreadPoints();
      if(TCU_EffectiveSpreadFilterEnabled() && spread > effectiveSlaveMaxSpread)
      {
         Print("[SLAVE] Spread too high for ", sym, ": ", spread, " > ", effectiveSlaveMaxSpread, " - skipping (will retry next scan)");
         WriteReport("SPREAD_SKIP", sym, typeStr, lots, masterTicket, 0, "spread="+IntegerToString(spread)+" max="+IntegerToString(effectiveSlaveMaxSpread));
         continue; // Don't add to copiedTickets - will retry when spread is OK
      }

      // [v6.01 FIX] Daily-loss kill-switch on the slave copy path. Previously
      // only the signal path (Telegram / Bridge / Discord) gated on this; a
      // misbehaving master could push the slave past its OWN daily limit on
      // the slave account. Skip without marking copied so the trade resumes
      // automatically once the limit clears (next day rollover).
      if(IsDailyLossLimitHit())
      {
         g_lastFilterReason = "Daily loss limit hit (slave)";
         Print("[SLAVE] Daily loss limit hit -- skipping copy of master #", masterTicket,
               ". Will retry on next scan or after day rollover.");
         WriteReport("DAILY_LOSS_SKIP", sym, typeStr, lots, masterTicket, 0,
                     "daily loss limit hit on slave account");
         continue;
      }

      // ReverseSignal for copier path
      if(ReverseSignal)
      {
         if(typeStr == "BUY") typeStr = "SELL";
         else if(typeStr == "SELL") typeStr = "BUY";
      }
      
      // Execute trade - open WITHOUT SL/TP for broker compatibility
      Print("[SLAVE] Copying: ", typeStr, " ", sym, " ", DoubleToString(lots, 2), " lots (spread=", spread, ")");
      bool ok = false;
      double price = 0;
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

      // Use the target symbol's supported fill mode, not the chart symbol's mode.
      g_trade.SetTypeFilling(DetectFillMode(sym));
      
      if(typeStr == "BUY")
      {
         price = SymbolInfoDouble(sym, SYMBOL_ASK);
      ok = g_trade.Buy(lots, sym, NormalizeDouble(price, digits), 0, 0, TCU_CopierTradeComment("Copy"));
      }
      else if(typeStr == "SELL")
      {
         price = SymbolInfoDouble(sym, SYMBOL_BID);
      ok = g_trade.Sell(lots, sym, NormalizeDouble(price, digits), 0, 0, TCU_CopierTradeComment("Copy"));
      }
      
      if(ok)
      {
         int idx = ArraySize(g_copiedTickets);
         ArrayResize(g_copiedTickets, idx + 1);
         g_copiedTickets[idx] = masterTicket;
         
         ulong slaveOrderTicket = g_trade.ResultOrder();
         ulong slaveDealTicket = g_trade.ResultDeal();
         ulong slaveTicket = ResolvePositionTicketFromTradeResult(sym, typeStr == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, slaveOrderTicket, slaveDealTicket);
         int mapIdx = -1;
         if(slaveTicket == 0 || !PositionSelectByTicket(slaveTicket))
         {
            if(TCU_RestoreSlaveMapForMaster(masterTicket, sym, typeStr, masterLots))
            {
               for(int mi = 0; mi < ArraySize(g_masterTicketMap); mi++)
               {
                  if(g_masterTicketMap[mi] == masterTicket)
                  {
                     mapIdx = mi;
                     break;
                  }
               }
               slaveTicket = (mapIdx >= 0 && mapIdx < ArraySize(g_slaveTickets)) ? g_slaveTickets[mapIdx] : 0;
               Print("[SLAVE] Fallback-linked newly copied master #", masterTicket, " to slave #", slaveTicket);
            }
         }
         if(mapIdx < 0)
         {
            mapIdx = ArraySize(g_masterTicketMap);
            ArrayResize(g_masterTicketMap, mapIdx + 1);
            ArrayResize(g_slaveTickets, mapIdx + 1);
            ArrayResize(g_masterLots, mapIdx + 1);
            g_masterTicketMap[mapIdx] = masterTicket;
         }
         else if(mapIdx >= ArraySize(g_masterLots))
         {
            ArrayResize(g_masterLots, mapIdx + 1);
         }
         g_slaveTickets[mapIdx] = slaveTicket;
         
         // Add SL/TP by modifying position afterward
         if((sl > 0 && CopySL) || (tp > 0 && CopyTP))
         {
            Sleep(SLTP_MODIFY_TIMEOUT); // Configurable timeout for position modification
            double syncSL = sl;
            double syncTP = tp;
            if(ReverseSignal)
            {
               if(syncSL > 0) syncSL = price + (masterEntry - syncSL);
               if(syncTP > 0) syncTP = price + (masterEntry - syncTP);
            }
            double normSL = (syncSL > 0 && CopySL) ? NormalizeDouble(syncSL, digits) : 0;
            double normTP = (syncTP > 0 && CopyTP) ? NormalizeDouble(syncTP, digits) : 0;
            if(slaveTicket > 0 && PositionSelectByTicket(slaveTicket))
               g_trade.PositionModify(slaveTicket, normSL, normTP);
            else
               Print("[SLAVE] Could not resolve/select live position for SL/TP modification");
         }
         
         // Track master lot size for partial close detection
         g_masterLots[mapIdx] = masterLots;
         
         g_tradesReceived++;
         Print("[SLAVE] SUCCESS! Slave ticket #", slaveTicket);
         WriteReport("COPIED", sym, typeStr, lots, masterTicket, slaveTicket, "price="+DoubleToString(price,digits));
         DoAlert("Copied: " + typeStr + " " + sym + " " + DoubleToString(lots, 2) + " lots");
         
         // Save state after successful copy
         SaveSlaveState();
      }
      else
      {
         Print("[SLAVE] FAILED! ", g_trade.ResultRetcode(), " - ", g_trade.ResultComment());
         WriteReport("COPY_FAIL", sym, typeStr, lots, masterTicket, 0, IntegerToString(g_trade.ResultRetcode())+" "+g_trade.ResultComment());
      }
   }
   
   FileClose(handle);
   
   // Mark initial sync as done only after we have a reliable first snapshot.
   // A single empty readable scan can happen while the master is rewriting the CSV.
   // A partially-written CSV can also expose only some master trades on the first pass.
   // Require the first non-empty snapshot to be stable across two scans before enabling copying.
   if(!g_initialSyncDone)
   {
      if(fileTicketCount > 0)
      {
         if(g_initialSyncSnapshotCount != fileTicketCount || g_initialSyncSnapshotHash != initialSyncSnapshotHash)
         {
            g_initialSyncSnapshotCount = fileTicketCount;
            g_initialSyncSnapshotHash = initialSyncSnapshotHash;
            g_initialSyncEmptyReadableScans = 0;
            Print("[SLAVE] Initial sync captured snapshot count=", fileTicketCount,
                  " hash=", (string)initialSyncSnapshotHash,
                  " - waiting for one stable re-scan before enabling copier.");
            g_scanInProgress = false;
            return;
         }

         g_initialSyncDone = true;
         g_initialSyncEmptyReadableScans = 0;
         Print("[SLAVE] Initial sync complete on stable snapshot - registered ", ArraySize(g_copiedTickets),
               " existing trade(s). Only NEW trades will be copied from now on.");
         SaveSlaveState();
      }
      else
      {
         g_initialSyncEmptyReadableScans++;
         if(g_initialSyncEmptyReadableScans < 3)
         {
            Print("[SLAVE] Initial sync saw empty readable snapshot ", g_initialSyncEmptyReadableScans,
                  "/3 - waiting for a stable file before enabling copier.");
            g_scanInProgress = false;
            return;
         }
         g_initialSyncDone = true;
         Print("[SLAVE] Initial sync complete on stable empty file - no master trades were present.");
      }
   }
   
   // Log scan results — only when file content changes or every 10s
   static ulong lastScanLog = 0;
   static int lastFileCount = -1;
   ulong now3 = GetTickCount64();
   if(fileTicketCount != lastFileCount || now3 - lastScanLog >= 10000)
   {
      Print("[SLAVE] File has ", fileTicketCount, " trade(s) | tracked=", 
            ArraySize(g_masterTicketMap), " | copied=", ArraySize(g_copiedTickets));
      lastScanLog = now3;
      lastFileCount = fileTicketCount;
   }
   
   // CLOSE MANAGEMENT: Close slave positions whose master tickets disappeared
   // Only runs if CopierAutoClose is enabled
   if(!CopierAutoClose) { g_scanInProgress = false; return; }
   
   // Race-condition safety: only act on close when file had real data
   int mapSz = ArraySize(g_masterTicketMap);
   
   if(mapSz == 0)
   {
      g_emptyReadCount = 0; // Nothing to close anyway
   }
   else if(fileTicketCount == 0)
   {
      // File has valid header but 0 trade rows. Instead of waiting for
      // COPIER_EMPTY_CLOSE_CONFIRM_READS separate timer ticks (each of which
      // can be delayed 2-5s by WebRequest calls in Telegram/Discord/Bridge),
      // do an inline re-verify: sleep briefly, re-read the file, confirm empty.
      // This matches the Simple EA's near-instant close behavior.
      bool fastConfirmed = false;
      Sleep(25);
      int h2 = FileOpen(CopierFileName, FILE_READ|FILE_CSV|FILE_COMMON|FILE_SHARE_WRITE|FILE_SHARE_READ, ',');
      if(h2 != INVALID_HANDLE)
      {
         int cols2 = 0;
         while(!FileIsEnding(h2))
         {
            FileReadString(h2);
            cols2++;
            if(FileIsLineEnding(h2)) break;
         }
         bool hasData = false;
         if(cols2 >= 8)
         {
            while(!FileIsEnding(h2))
            {
               string chk = FileReadString(h2);
               if(StringLen(chk) > 0 && (ulong)StringToInteger(chk) > 0)
                  hasData = true;
               break;
            }
         }
         FileClose(h2);
         if(cols2 >= 8 && !hasData)
            fastConfirmed = true;
      }

      if(fastConfirmed)
      {
         g_emptyReadCount = COPIER_EMPTY_CLOSE_CONFIRM_READS;
         Print("[SLAVE] Master file confirmed empty (fast verify) -- closing all ", mapSz, " slave positions");
      }
      else
      {
         // File locked or race condition -- fall back to multi-tick counter
         g_emptyReadCount++;
         if(g_emptyReadCount < COPIER_EMPTY_CLOSE_CONFIRM_READS)
         {
            g_scanInProgress = false;
            return;
         }
         Print("[SLAVE] Master file empty for ", COPIER_EMPTY_CLOSE_CONFIRM_READS, " reads -- closing all ", mapSz, " slave positions");
      }
   }
   else
   {
      g_emptyReadCount = 0; // Got real data, reset counter
   }
   
   // Optimize: Collect indices to remove first, then remove in reverse order to avoid O(n^2)
   int indicesToRemove[];
   int removeCount = 0;
   
   for(int i = 0; i < mapSz; i++)
   {
      bool stillInFile = false;
      for(int j = 0; j < fileTicketCount; j++)
      {
         if(fileTickets[j] == g_masterTicketMap[i]) { stillInFile = true; break; }
      }
      
      if(!stillInFile)
      {
         ArrayResize(indicesToRemove, removeCount + 1);
         indicesToRemove[removeCount] = i;
         removeCount++;
      }
   }
   
   // Remove entries in reverse order to maintain array indices
   for(int r = removeCount - 1; r >= 0; r--)
   {
      int i = indicesToRemove[r];
      ulong closedMasterTicket = g_masterTicketMap[i];
      ulong slaveTicket = g_slaveTickets[i];
      
      if(PositionSelectByTicket(slaveTicket))
      {
         string closeSym = PositionGetString(POSITION_SYMBOL);
         string closeDir = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         double closeVol = PositionGetDouble(POSITION_VOLUME);
         Print("[SLAVE] Master closed #", closedMasterTicket, " - closing slave #", slaveTicket);
         if(g_trade.PositionClose(slaveTicket))
         {
            WriteReport("AUTO_CLOSE", closeSym, closeDir, closeVol, closedMasterTicket, slaveTicket, "master closed");
            DoAlert("Auto-closed slave #" + IntegerToString((long)slaveTicket));
         }
      }
      else
      {
         Print("[SLAVE] Position #", slaveTicket, " already closed (master #", closedMasterTicket, ")");
         WriteReport("ALREADY_CLOSED", "", "", 0, closedMasterTicket, slaveTicket, "position not found");
      }
      
      // Remove from arrays by shifting elements left
      for(int k = i; k < mapSz - 1; k++)
      {
         g_masterTicketMap[k] = g_masterTicketMap[k + 1];
         g_slaveTickets[k] = g_slaveTickets[k + 1];
         if(k < ArraySize(g_masterLots) - 1)
            g_masterLots[k] = g_masterLots[k + 1];
      }
      mapSz--;
      
      // Resize arrays
      ArrayResize(g_masterTicketMap, mapSz);
      ArrayResize(g_slaveTickets, mapSz);
      ArrayResize(g_masterLots, mapSz);
      
      // Remove from copiedTickets array
      int copSz = ArraySize(g_copiedTickets);
      for(int k = 0; k < copSz; k++)
      {
         if(g_copiedTickets[k] == closedMasterTicket)
         {
            for(int m = k; m < copSz - 1; m++)
               g_copiedTickets[m] = g_copiedTickets[m + 1];
            ArrayResize(g_copiedTickets, copSz - 1);
            break;
         }
      }
   }
   
   // CLEANUP: Remove unlinked copiedTickets entries that disappeared from CSV.
   // These are master tickets registered during initial sync that had no slave
   // position to link to. When master closes them, we just remove from copiedTickets.
   if(fileTicketCount > 0 || g_emptyReadCount >= COPIER_EMPTY_CLOSE_CONFIRM_READS)
   {
      int copSzClean = ArraySize(g_copiedTickets);
      for(int c = copSzClean - 1; c >= 0; c--)
      {
         // Check if this copiedTicket is still in the CSV file
         bool inFile = false;
         for(int j = 0; j < fileTicketCount; j++)
         {
            if(fileTickets[j] == g_copiedTickets[c]) { inFile = true; break; }
         }
         if(inFile) continue;
         
         // Check if it's tracked in masterTicketMap (already handled above)
         bool inMap = false;
         int curMapSz = ArraySize(g_masterTicketMap);
         for(int j = 0; j < curMapSz; j++)
         {
            if(g_masterTicketMap[j] == g_copiedTickets[c]) { inMap = true; break; }
         }
         if(inMap) continue;
         
         // Unlinked and gone from CSV — remove from copiedTickets
         Print("[SLAVE] Removing stale unlinked master #", g_copiedTickets[c], " from copiedTickets");
         for(int m = c; m < copSzClean - 1; m++)
            g_copiedTickets[m] = g_copiedTickets[m + 1];
         copSzClean--;
         ArrayResize(g_copiedTickets, copSzClean);
      }
   }
   g_scanInProgress = false;
}

//+------------------------------------------------------------------+
// Check if slave already has an open position with the same symbol and direction
// Returns the ticket if found, 0 if not found
// Skips tickets already present in g_slaveTickets to prevent double-linking
ulong SlaveHasPosition(string sym, string dir)
{
   ENUM_POSITION_TYPE lookFor = POSITION_TYPE_BUY;
   if(dir == "SELL") lookFor = POSITION_TYPE_SELL;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      // [v6.01 FIX] Match only positions OUR copier opened. Without this magic
      // filter, a manual trade (or a different EA's trade) on the same sym+dir
      // could be "linked" to a master ticket on initial sync and then
      // auto-closed when the master closes -- the user's own unrelated trade
      // gets nuked. Slave copies always carry MagicNumber via
      // g_trade.SetExpertMagicNumber() at OnInit; manual trades carry magic 0.
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(posMagic != MagicNumber) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == lookFor)
      {
         // Check if this slave ticket is already linked to another master ticket
         bool alreadyLinked = false;
         int slvSz = ArraySize(g_slaveTickets);
         for(int k = 0; k < slvSz; k++)
         {
            if(g_slaveTickets[k] == ticket)
            {
               alreadyLinked = true;
               break;
            }
         }
         if(alreadyLinked)
         {
            Print("[SLAVE] Skipping already-linked slave #", ticket, " for ", sym, " ", dir);
            continue;  // Keep searching for another unlinked position
         }
         return ticket;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
// Save slave state to persistent file
void SaveSlaveState()
{
   if(StringLen(g_stateFileName) == 0) return;
   int handle = FileOpen(g_stateFileName, FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("[STATE] WARNING: Could not save state file!");
      return;
   }
   
   int sz = ArraySize(g_masterTicketMap);
   FileWrite(handle, "MasterTicket", "SlaveTicket", "MasterLots");
   for(int i = 0; i < sz; i++)
   {
      double lots = (i < ArraySize(g_masterLots)) ? g_masterLots[i] : 0;
      FileWrite(handle, g_masterTicketMap[i], g_slaveTickets[i], DoubleToString(lots, 4));
   }
   
   FileClose(handle);
   Print("[STATE] Saved ", sz, " tracked position(s) to ", g_stateFileName);
}

//+------------------------------------------------------------------+
// Load slave state from persistent file
void LoadSlaveState()
{
   if(StringLen(g_stateFileName) == 0) return;
   int handle = FileOpen(g_stateFileName, FILE_READ|FILE_CSV|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("[STATE] No saved state file -- fresh start (will use live position check as fallback)");
      return;
   }
   
   // Skip header (3 columns)
   FileReadString(handle); FileReadString(handle); FileReadString(handle);
   
   int loaded = 0;
   while(!FileIsEnding(handle))
   {
      string mStr = FileReadString(handle);
      if(StringLen(mStr) == 0) break;
      string sStr = FileReadString(handle);
      string lStr = FileReadString(handle);
      
      ulong masterTicket = (ulong)StringToInteger(mStr);
      ulong slaveTicket = (ulong)StringToInteger(sStr);
      double masterLots = StringToDouble(lStr);
      
      if(masterTicket == 0) continue;  // Skip invalid entries
      
      int idx = ArraySize(g_masterTicketMap);
      ArrayResize(g_masterTicketMap, idx + 1);
      ArrayResize(g_slaveTickets, idx + 1);
      ArrayResize(g_copiedTickets, idx + 1);
      ArrayResize(g_masterLots, idx + 1);
      g_masterTicketMap[idx] = masterTicket;
      g_slaveTickets[idx] = slaveTicket;
      g_copiedTickets[idx] = masterTicket;
      g_masterLots[idx] = masterLots;
      loaded++;
   }
   FileClose(handle);
   
   // CRITICAL: Validate loaded state - remove entries for closed slave positions
   // Keep stale master tickets in g_copiedTickets so we don't re-copy them!
   int validCount = 0;
   ulong staleMasterTickets[];
   int staleCount = 0;
   
   for(int i = 0; i < loaded; i++)
   {
      ulong slaveTicket = g_slaveTickets[i];
      
      // Check if slave position still exists
      if(PositionSelectByTicket(slaveTicket))
      {
         // Position exists - keep this entry fully tracked
         if(validCount != i)
         {
            // Shift down to fill gaps
            g_masterTicketMap[validCount] = g_masterTicketMap[i];
            g_slaveTickets[validCount] = g_slaveTickets[i];
            g_copiedTickets[validCount] = g_copiedTickets[i];
            g_masterLots[validCount] = g_masterLots[i];
         }
         validCount++;
      }
      else
      {
         // Slave position gone -- remove from active tracking but KEEP master ticket
         // in copiedTickets so we don't try to re-copy it
         Print("[STATE] Slave position #", slaveTicket, " no longer exists - removing from tracking (keeping in copiedTickets)");
         ArrayResize(staleMasterTickets, staleCount + 1);
         staleMasterTickets[staleCount] = g_copiedTickets[i];
         staleCount++;
      }
   }
   
   // Resize active tracking arrays to valid count
   if(validCount < loaded)
   {
      ArrayResize(g_masterTicketMap, validCount);
      ArrayResize(g_slaveTickets, validCount);
      ArrayResize(g_masterLots, validCount);
      
      // Rebuild g_copiedTickets: valid entries + stale master tickets
      ArrayResize(g_copiedTickets, validCount + staleCount);
      // Valid entries are already in the first validCount slots
      for(int s = 0; s < staleCount; s++)
      {
         // Fix: Check for duplicates before adding stale master tickets
         bool alreadyExists = false;
         for(int v = 0; v < validCount; v++)
         {
            if(g_copiedTickets[v] == staleMasterTickets[s])
            {
               alreadyExists = true;
               break;
            }
         }
         // Only add if not already in valid entries
         if(!alreadyExists)
            g_copiedTickets[validCount + s] = staleMasterTickets[s];
      }
      
      Print("[STATE] Cleaned ", loaded - validCount, " stale entries (kept ", staleCount, " master tickets in copiedTickets to prevent re-copy)");
      loaded = validCount;
      SaveSlaveState();  // Save cleaned state
   }
   
   if(loaded > 0)
      Print("[STATE] Restored ", loaded, " tracked position(s) from saved state");
   else
      Print("[STATE] Saved state empty -- live position check will prevent duplicates");
}

//+------------------------------------------------------------------+
// Save Bot API state (last update ID) to prevent replaying old messages
void SaveBotState()
{
   if(StringLen(g_botStateFileName) == 0) return;
   int handle = FileOpen(g_botStateFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      Print("[BotAPI] WARNING: Could not save bot state file!");
      return;
   }
   FileWriteString(handle, IntegerToString(g_lastUpdateId));
   FileClose(handle);
}

//+------------------------------------------------------------------+
// Flush all old Telegram messages at startup so they are never replayed.
// Uses Telegram's offset=-1 trick to jump to the latest update, then
// confirms with offset=latest+1 to mark everything as read.
// [v6.01] Activate Bot API mode at runtime (panel toggle path). Re-stamps the
// session start time and re-runs the flush so messages received before the
// toggle cannot be replayed. Idempotent -- safe to call multiple times.
void TCU_BotApiActivate()
{
   g_botSessionStartTime = TimeGMT();
   g_botFirstPollDone = false;
   if(StringLen(g_botStateFileName) == 0) g_botStateFileName = "TCU_BotState.dat";
   FlushOldTelegramMessages();
   Print("[BotAPI] Activated at runtime. Session start = ", TimeToString(g_botSessionStartTime, TIME_DATE|TIME_SECONDS), " GMT. Old messages will be ignored.");
}

//+------------------------------------------------------------------+
// [v6.02] Activate Bridge mode at runtime (panel toggle path).
// Re-arms the startup drain window so any signals buffered while Bridge
// mode was OFF are treated as stale and cleared on the first live poll.
void TCU_BridgeActivate()
{
   g_bridgeFailCount = 1;
   g_bridgeNextRetry = GetTickCount64() + 5000;
   g_bridgeFirstPoll = true;
   g_startupTickCount = GetTickCount64();
   Print("[Bridge] Activated at runtime. Deferred first poll by 5s and re-armed stale-signal drain.");
}

//+------------------------------------------------------------------+
void FlushOldTelegramMessages()
{
   if(StringLen(TelegramBotToken) < 10) return;
   
   // Step 1: Get only the latest update using offset=-1
   string url = TELEGRAM_URL + TelegramBotToken + "/getUpdates?offset=-1&timeout=0";
   char post[];
   char result[];
   string headers = "";
   
   ResetLastError();
   // [v6.00 FIX 2026-04-26][R3] WebRequest timeout 500ms -> 5000ms (same reason as PollTelegram).
   int res = WebRequest("GET", url, headers, 5000, post, result, headers);
   if(res != 200)
   {
      Print("[BotAPI] Flush: WebRequest failed (", res, "), will skip old messages on first poll");
      return;
   }
   
   string response = CharArrayToString(result);
   
   // Extract the latest update_id
   int uPos = StringFind(response, "\"update_id\":");
   if(uPos >= 0)
   {
      int uEnd = StringFind(response, ",", uPos + 12);
      if(uEnd < 0) uEnd = StringFind(response, "}", uPos + 12);
      string uStr = StringSubstr(response, uPos + 12, uEnd - uPos - 12);
      int latestId = (int)StringToInteger(uStr);
      
      if(latestId > 0)
      {
         g_lastUpdateId = latestId;
         
         // Step 2: Confirm by calling with offset=latest+1 (marks all as read)
         string confirmUrl = TELEGRAM_URL + TelegramBotToken + "/getUpdates?offset=" + IntegerToString(latestId + 1) + "&timeout=0";
         ArrayFree(result);
         // [v6.00 FIX 2026-04-26][R3] Confirm-call timeout 500ms -> 5000ms.
         WebRequest("GET", confirmUrl, headers, 5000, post, result, headers);
         
         SaveBotState();
         Print("[BotAPI] Flushed old messages. Latest update_id=", latestId, ". Only NEW messages will be processed.");
      }
   }
   else
   {
      Print("[BotAPI] No pending messages found. Ready for new signals.");
   }
   
   g_botFirstPollDone = true; // Mark as ready -- no need to skip first poll anymore
}

//+------------------------------------------------------------------+
// MANUAL PARTIAL CLOSE: Monitor positions and close portions at pip targets
//+------------------------------------------------------------------+
bool PartialLevelEnabled(int lvl)
{
   if(lvl == 1) return PartialTP1Pips > 0;
   if(lvl == 2) return PartialTP2Pips > 0;
   if(lvl == 3) return PartialTP3Pips > 0;
   if(lvl == 4) return PartialTP4Pips > 0;
   return false;
}

double PartialLevelPips(int lvl)
{
   if(lvl == 1) return PartialTP1Pips;
   if(lvl == 2) return PartialTP2Pips;
   if(lvl == 3) return PartialTP3Pips;
   if(lvl == 4) return PartialTP4Pips;
   return 0;
}

double PartialLevelLots(int lvl)
{
   if(lvl == 1) return PartialTP1Lots;
   if(lvl == 2) return PartialTP2Lots;
   if(lvl == 3) return PartialTP3Lots;
   if(lvl == 4) return PartialTP4Lots;
   return 0;
}

double PartialLevelPercent(int lvl)
{
   if(lvl == 1) return PartialTP1Percent;
   if(lvl == 2) return PartialTP2Percent;
   if(lvl == 3) return PartialTP3Percent;
   if(lvl == 4) return PartialTP4Percent;
   return 0;
}

bool PartialLevelDone(int idx, int lvl)
{
   if(idx < 0 || idx >= g_partialCount) return true;
   if(lvl == 1) return g_partialTP1Done[idx];
   if(lvl == 2) return g_partialTP2Done[idx];
   if(lvl == 3) return g_partialTP3Done[idx];
   if(lvl == 4) return g_partialTP4Done[idx];
   return true;
}

void SetPartialLevelDone(int idx, int lvl, bool done)
{
   if(idx < 0 || idx >= g_partialCount) return;
   if(lvl == 1) g_partialTP1Done[idx] = done;
   else if(lvl == 2) g_partialTP2Done[idx] = done;
   else if(lvl == 3) g_partialTP3Done[idx] = done;
   else if(lvl == 4) g_partialTP4Done[idx] = done;
}

bool PreviousPartialLevelsDone(int idx, int lvl)
{
   for(int j = 1; j < lvl; j++)
      if(PartialLevelEnabled(j) && !PartialLevelDone(idx, j))
         return false;
   return true;
}

bool AllPartialLevelsDoneOrInactive(int idx)
{
   for(int j = 1; j <= 4; j++)
      if(PartialLevelEnabled(j) && !PartialLevelDone(idx, j))
         return false;
   return true;
}

bool PartialMoveSLAfterLevel(int lvl)
{
   if(lvl == 1) return PartialMoveSLBreakeven;
   if(lvl == 2) return PartialMoveSLToTP1;
   if(lvl == 3) return PartialMoveSLToTP2;
   if(lvl == 4) return PartialMoveSLToTP3;
   return false;
}

double PartialMoveSLTargetPrice(int lvl, bool isBuy, double entryPrice, double pipSize, int digits)
{
   if(lvl == 1)
   {
      double bePips = PartialBEExtraPips * pipSize;
      return isBuy ? NormalizeDouble(entryPrice + bePips, digits)
                   : NormalizeDouble(entryPrice - bePips, digits);
   }
   double targetPips = PartialLevelPips(lvl - 1);
   if(targetPips <= 0) return 0;
   return isBuy ? NormalizeDouble(entryPrice + targetPips * pipSize, digits)
                : NormalizeDouble(entryPrice - targetPips * pipSize, digits);
}

bool IsTrackedMultiTPTicket(ulong ticket)
{
   for(int i = 0; i < g_mtpCount; i++)
      if(g_mtpTickets[i] == ticket) return true;
   return false;
}

string PartialLevelSummary(int lvl)
{
   if(lvl < 1 || lvl > 4) return "";
   string total = "4";
   if(PartialTP4Pips <= 0) total = "3";
   if(PartialTP3Pips <= 0) total = "2";
   if(PartialTP2Pips <= 0) total = "1";
   return IntegerToString(lvl) + "/" + total;
}

void ManagePartialClose()
{
   if(g_partialCount == 0) return;
   for(int i = g_partialCount - 1; i >= 0; i--)
   {
      ulong ticket = g_partialTickets[i];
      if(!PositionSelectByTicket(ticket)) { RemovePartialEntry(i); continue; }
      if(PartialScope == PARTIAL_SCOPE_AUTO && IsTrackedMultiTPTicket(ticket))
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentLots = PositionGetDouble(POSITION_VOLUME);
      double currentSL = PositionGetDouble(POSITION_SL);
      bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double pipSize = PipSize(sym);
      double currentPrice = isBuy ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      double profitPips = isBuy ? (currentPrice - entryPrice) / pipSize : (entryPrice - currentPrice) / pipSize;
      double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN); if(minL <= 0) minL = 0.01;
      double stepL = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP); if(stepL <= 0) stepL = 0.01;

      for(int lvl = 1; lvl <= 4; lvl++)
      {
         if(!PartialLevelEnabled(lvl) || PartialLevelDone(i, lvl)) continue;
         if(!PreviousPartialLevelsDone(i, lvl)) continue;
         double targetPips = PartialLevelPips(lvl);
         if(targetPips <= 0 || profitPips < targetPips) continue;

         if(!PositionSelectByTicket(ticket)) { RemovePartialEntry(i); continue; }
         currentLots = PositionGetDouble(POSITION_VOLUME);
         double closeLots = CalcPartialLots(PartialLevelLots(lvl), PartialLevelPercent(lvl),
                                            g_partialOrigLots[i], currentLots, minL, stepL);
         if(closeLots <= 0 || closeLots > currentLots) continue;

         g_trade.SetTypeFilling(DetectFillMode(sym));
         if(g_trade.PositionClosePartial(ticket, closeLots))
         {
            SetPartialLevelDone(i, lvl, true);
            Print("[PARTIAL] TP", lvl, " hit at ", DoubleToString(profitPips, 1),
                  " pips. Closed ", DoubleToString(closeLots, 2), " lots");
            if(EnablePartialAlerts)
            {
               string sizeText = (PartialCloseMode == PARTIAL_FIXED_LOTS)
                  ? (DoubleToString(closeLots, 2) + " lots")
                  : (DoubleToString(PartialLevelPercent(lvl), 1) + "%");
               DoAlert(sym + ": Partial " + PartialLevelSummary(lvl) + " closed at " +
                       DoubleToString(targetPips, 1) + " pips (" + sizeText + ")");
            }

            if(PartialMoveSLAfterLevel(lvl))
            {
               double newSL = PartialMoveSLTargetPrice(lvl, isBuy, entryPrice, pipSize, digits);
               bool shouldMove = isBuy ? (currentSL < newSL || currentSL == 0) : (currentSL > newSL || currentSL == 0);
               if(newSL > 0 && shouldMove && PositionSelectByTicket(ticket))
               {
                  double curTP = PositionGetDouble(POSITION_TP);
                  if(g_trade.PositionModify(ticket, newSL, curTP))
                  {
                     string moveName = (lvl == 1 ? "breakeven" : "TP" + IntegerToString(lvl - 1));
                     Print("[PARTIAL] SL moved to ", moveName, ": ", DoubleToString(newSL, digits));
                  }
               }
            }
         }
      }

      if(AllPartialLevelsDoneOrInactive(i))
         RemovePartialEntry(i);
   }
}

//+------------------------------------------------------------------+
double CalcPartialLots(double fixedLots, double pctOfOrig, double origLots, double currentLots, double minL, double stepL)
{
   double lots = 0;
   if(PartialCloseMode == PARTIAL_FIXED_LOTS)
   {
      if(fixedLots > 0) lots = fixedLots;
      else return 0;
   }
   else
   {
      if(pctOfOrig > 0) lots = origLots * pctOfOrig / 100.0;
      else return 0;
   }
   lots = MathFloor(lots / stepL + 0.0000001) * stepL;
   if(lots < minL) lots = minL;
   if(lots > currentLots) lots = currentLots;
   return lots;
}

//+------------------------------------------------------------------+
void RemovePartialEntry(int idx)
{
   for(int r = idx; r < g_partialCount - 1; r++)
   {
      g_partialTickets[r] = g_partialTickets[r + 1];
      g_partialTP1Done[r] = g_partialTP1Done[r + 1];
      g_partialTP2Done[r] = g_partialTP2Done[r + 1];
      g_partialTP3Done[r] = g_partialTP3Done[r + 1];
      g_partialTP4Done[r] = g_partialTP4Done[r + 1];
      g_partialOrigLots[r] = g_partialOrigLots[r + 1];
   }
   g_partialCount--;
   ArrayResize(g_partialTickets, g_partialCount);
   ArrayResize(g_partialTP1Done, g_partialCount);
   ArrayResize(g_partialTP2Done, g_partialCount);
   ArrayResize(g_partialTP3Done, g_partialCount);
   ArrayResize(g_partialTP4Done, g_partialCount);
   ArrayResize(g_partialOrigLots, g_partialCount);
}

//+------------------------------------------------------------------+
// TELEGRAM MULTI-TP: Move SL when sub-positions close
//+------------------------------------------------------------------+
void ManagePendingExpiry()
{
   int sz = ArraySize(g_pendingExpTickets);
   if(sz == 0) return;
   datetime now = TimeCurrent();
   long expirySeconds = (long)PendingExpiryHours * 3600;
   for(int i = sz - 1; i >= 0; i--)
   {
      ulong ticket = g_pendingExpTickets[i];
      if(now - g_pendingExpTimes[i] < expirySeconds) continue;
      // Check if order is still pending (not filled or cancelled)
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_STATE) == ORDER_STATE_PLACED)
      {
         Print("[EXPIRY] Pending order #", ticket, " expired after ", PendingExpiryHours, "h -- deleting");
         g_trade.OrderDelete(ticket);
         WriteReport("EXPIRED", OrderGetString(ORDER_SYMBOL), "", OrderGetDouble(ORDER_VOLUME_CURRENT), 0, ticket, "auto-expired");
      }
      // Remove from tracking (whether deleted or already gone)
      int newSz = sz - 1;
      for(int j = i; j < newSz; j++)
      {
         g_pendingExpTickets[j] = g_pendingExpTickets[j+1];
         g_pendingExpTimes[j]   = g_pendingExpTimes[j+1];
      }
      ArrayResize(g_pendingExpTickets, newSz);
      ArrayResize(g_pendingExpTimes,   newSz);
      sz = newSz;
   }
}

// [v6.00 FIX 2026-04-26][R1] Helper: determine if a closed position closed via TP.
// Inspects the closing OUT deal in history. Trusts DEAL_REASON if the broker tags it cleanly,
// otherwise falls back to comparing the deal close price against the expected TP (~3 pips
// tolerance, scales with broker digit precision).
//
// CRITICAL: must return false on SL hit / Stop-out / manual close, otherwise ManageMultiTP()
// will incorrectly escalate the SL of remaining children when the first leg was actually
// stopped out (real-money bug pre-fix).
bool MultiTP_ClosedByTP(ulong ticket, double expectedTP)
{
   if(!HistorySelectByPosition((long)ticket))
      HistorySelect(TimeCurrent() - 86400, TimeCurrent() + 60);
   int totalDeals = HistoryDealsTotal();
   for(int d = totalDeals - 1; d >= 0; d--)
   {
      ulong dealTicket = HistoryDealGetTicket(d);
      if(dealTicket == 0) continue;
      ulong dealPosId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      if(dealPosId != ticket) continue;
      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
      long reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      if(reason == DEAL_REASON_TP) return true;
      if(reason == DEAL_REASON_SL || reason == DEAL_REASON_SO) return false;
      // Broker didn't tag DEAL_REASON cleanly -- fall back to price proximity vs expected TP.
      // [v6.00 FIX 2026-04-26][R8] Pip-aware tolerance. Original code used 30*point which
      // is ~3 pips on 5-digit FX but ~30 index points on US30 (point=1.0) and ~0.30 on gold
      // (point=0.01) -- way too loose, would false-positive a stop-out as TP-hit on those.
      // Now we resolve a real "pip" per asset class: FX 3/5-digit pip = 10*point; everything
      // else (4/2/1-digit indices, metals, crypto) pip == point. Tolerance = 3 pips uniformly.
      if(expectedTP > 0)
      {
         string dealSym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
         double point   = SymbolInfoDouble(dealSym, SYMBOL_POINT);
         int    digits  = (int)SymbolInfoInteger(dealSym, SYMBOL_DIGITS);
         if(point <= 0) point = 0.00001;
         double pipSize = (digits == 3 || digits == 5) ? point * 10.0 : point;
         double tolerance = 3.0 * pipSize;  // ~3 pips on every asset class
         double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         if(MathAbs(dealPrice - expectedTP) <= tolerance) return true;
      }
      return false;
   }
   return false;  // No matching closing deal found -- be safe, do NOT escalate SL.
}

void ManageMultiTP()
{
   if(g_mtpCount == 0) return;
   for(int i = g_mtpCount - 1; i >= 0; i--)
   {
      ulong ticket = g_mtpTickets[i];
      if(PositionSelectByTicket(ticket)) continue; // Still open
      int closedTPIdx = g_mtpTPIndex[i];
      string groupID = g_mtpGroupIDs[i];
      double entryPrice = g_mtpEntryPrices[i];
      double closedTPPrice = g_mtpTPPrices[i];
      // [v6.00 FIX 2026-04-26][R1] Only escalate SL on TP-hit, NOT on stop-out/manual close.
      // Pre-fix behavior: ManageMultiTP saw "position closed" and unconditionally moved
      // remaining children's SL to breakeven (TP1 closed) or to TP1 price (TP2 closed).
      // This was wrong when the leg was stopped out -- the EA would push the surviving
      // legs' SL up to a worse exit, locking in additional loss.
      bool wasTPHit = MultiTP_ClosedByTP(ticket, closedTPPrice);
      if(!wasTPHit)
      {
         Print("[MULTI-TP] #", ticket, " (TP", closedTPIdx, " leg) closed but NOT via TP -- ",
               "skipping SL escalation for sibling legs to avoid worsening surviving SL.");
      }
      // Adjust SL of remaining positions in same group (only when TP was actually hit)
      for(int j = 0; j < g_mtpCount && wasTPHit; j++)
      {
         if(j == i || g_mtpGroupIDs[j] != groupID) continue;
         ulong rt = g_mtpTickets[j];
         if(!PositionSelectByTicket(rt)) continue;
         string sym = PositionGetString(POSITION_SYMBOL);
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         bool isBuyPos = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double newSL = curSL;
         bool needModify = false;
         if(closedTPIdx == 1 && TGMoveSLBreakevenTP1)
         {
            newSL = BreakevenSLPrice(sym, isBuyPos, entryPrice, TGBreakevenExtraPips);
            if(isBuyPos && (curSL < newSL || curSL == 0)) needModify = true;
            else if(!isBuyPos && (curSL > newSL || curSL == 0)) needModify = true;
         }
         if(closedTPIdx == 2 && TGMoveSLToTP1OnTP2)
         {
            double tp1p = 0;
            for(int k = 0; k < g_mtpCount; k++)
               if(g_mtpGroupIDs[k] == groupID && g_mtpTPIndex[k] == 1) { tp1p = g_mtpTPPrices[k]; break; }
            if(tp1p > 0) { newSL = NormalizeDouble(tp1p, digits); needModify = true; }
         }
         if(needModify && g_trade.PositionModify(rt, newSL, curTP))
            Print("[MULTI-TP] SL modified for #", rt, " newSL=", newSL);
      }
      // Remove closed entry
      for(int r = i; r < g_mtpCount - 1; r++)
      {
         g_mtpGroupIDs[r] = g_mtpGroupIDs[r+1]; g_mtpTickets[r] = g_mtpTickets[r+1];
         g_mtpTPIndex[r] = g_mtpTPIndex[r+1]; g_mtpTPPrices[r] = g_mtpTPPrices[r+1];
         g_mtpEntryPrices[r] = g_mtpEntryPrices[r+1];
      }
      g_mtpCount--;
      ArrayResize(g_mtpGroupIDs, g_mtpCount); ArrayResize(g_mtpTickets, g_mtpCount);
      ArrayResize(g_mtpTPIndex, g_mtpCount); ArrayResize(g_mtpTPPrices, g_mtpCount);
      ArrayResize(g_mtpEntryPrices, g_mtpCount);
   }
}

//+------------------------------------------------------------------+
void SetMinimized(bool mini)
{
   g_minimized = mini;
   int total = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PREFIX) != 0) continue;
      if(name == PREFIX+"BG" || name == PREFIX+"HDR" || name == PREFIX+"GLOW"
         || name == PREFIX+"TITLE" || name == PREFIX+"BTN_MIN") continue;
      ShowObject(name, !mini);
   }
   ObjectSetString(0, PREFIX+"BTN_MIN", OBJPROP_TEXT, mini ? "+" : "_");
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_YSIZE, mini ? 30 : g_panelH);
   ChartRedraw();
}

//+------------------------------------------------------------------+
void MovePanel(int newX, int newY)
{
   int dx = newX - g_panelX, dy = newY - g_panelY;
   if(dx == 0 && dy == 0) return;
   int total = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PREFIX) != 0) continue;
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) + dx);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) + dy);
   }
   g_panelX = newX; g_panelY = newY;
   ChartRedraw();
}

//+------------------------------------------------------------------+
void ShowObject(string n, bool visible)
{
   if(ObjectFind(0, n) >= 0)
      ObjectSetInteger(0, n, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
}

//+------------------------------------------------------------------+
void CreatePanel()
{
   ObjectsDeleteAll(0, PREFIX);
   TCU_DrawUI();
}

//+------------------------------------------------------------------+
void CreateCompactPanel()
{
   int x=g_panelX, y=g_panelY;
   g_panelW=220; g_panelH=90;
   GUIRect(PREFIX+"BG",x,y,g_panelW,g_panelH,g_clrBG,g_clrBorder);
   GUIRect(PREFIX+"HDR",x,y,g_panelW,28,g_clrHDR,g_clrBorder);
   GUIRect(PREFIX+"GLOW",x,y+28,g_panelW,2,g_clrAccent,g_clrAccent);
   GUILabel(PREFIX+"TITLE",x+8,y+7,"Trade Copier Ultimate",g_clrAccent,8,"Segoe UI Bold");
   GUIButton(PREFIX+"BTN_SETTINGS",x+g_panelW-52,y+3,22,22,"[=]",g_clrHDR,g_clrAccent);
   GUIButton(PREFIX+"BTN_MIN",x+g_panelW-26,y+3,22,22,"_",g_clrHDR,g_clrDim);
   int by=y+34;
   GUILabel(PREFIX+"L_MODE",x+8,by,"Mode",g_clrDim,7);
   GUILabel(PREFIX+"VAL_MODE",x+55,by,"---",g_clrText,7,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_RECV",x+8,by,"Copied",g_clrDim,7);
   GUILabel(PREFIX+"VAL_RECV",x+55,by,"0",g_clrSafe,7,"Segoe UI Bold");
   GUILabel(PREFIX+"L_BAL2",x+110,by,"Bal",g_clrDim,7);
   GUILabel(PREFIX+"VAL_BAL",x+130,by,"---",g_clrWarn,7,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"VAL_ARM",x+8,by,"ARMED",g_clrSafe,7,"Segoe UI Bold");
   GUILabel(PREFIX+"BRAND",x+80,by,"* NTS",g_clrDim,6);
   // Hidden compat
   GUILabel(PREFIX+"VAL_SENT",-999,-999,"0",g_clrText,1);
   GUILabel(PREFIX+"VAL_SIG",-999,-999,"0",g_clrText,1);
   GUILabel(PREFIX+"V_PCLOSE",-999,-999,"0",g_clrText,1);
   GUILabel(PREFIX+"VAL_EQ",-999,-999,"---",g_clrText,1);
   GUILabel(PREFIX+"VAL_ERR",-999,-999,"Ready",g_clrSafe,1);
   GUILabel(PREFIX+"VAL_LST",-999,-999,"None",g_clrText,1);
   GUILabel(PREFIX+"VAL_FILT",-999,-999,"None",g_clrDim,1);
   GUILabel(PREFIX+"V_BRIDGE",-999,-999,"---",g_clrDim,1);
   GUILabel(PREFIX+"V_TG",-999,-999,"---",g_clrDim,1);
   GUILabel(PREFIX+"VAL_SYM",-999,-999,_Symbol,g_clrText,1);
   GUIButton(PREFIX+"BTN_TEST",-999,-999,10,10,"TEST",g_clrHDR,g_clrDim);
   ChartRedraw();
}

void CreateFullPanel()
{
   int x=g_panelX, y=g_panelY;
   g_panelW=220; g_panelH=370;
   // Background
   GUIRect(PREFIX+"BG",   x,y,g_panelW,g_panelH,g_clrBG,g_clrBorder);
   // Header
   GUIRect(PREFIX+"HDR",  x,y,g_panelW,24,C'25,26,40',g_clrBorder);
   GUILabel(PREFIX+"TITLE",x+8,y+5,"TRADE COPIER ULTIMATE",clrWhite,8,"Segoe UI Bold");
   int by=y+26;
   // NTS branding
   GUIRect(PREFIX+"BRAND_BG",x,by,g_panelW,14,C'18,20,32',g_clrBorder);
   GUILabel(PREFIX+"BRAND",x+8,by+1,"Navigator Trading Systems",C'80,85,100',6,"Segoe UI");
   by+=18;
   GUIRect(PREFIX+"DIV0",x+8,by,g_panelW-16,1,g_clrBorder,g_clrBorder); by+=6;
   // Connection status
   GUILabel(PREFIX+"L_BR", x+8,by,"Bridge",g_clrDim,8);
   GUILabel(PREFIX+"V_BRIDGE",x+80,by,"---",g_clrDim,7,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_TG", x+8,by,"Telegram",g_clrDim,8);
   GUILabel(PREFIX+"V_TG",x+80,by,"---",g_clrDim,7,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_MODE",x+8,by,"Mode",g_clrDim,8);
   GUILabel(PREFIX+"VAL_MODE",x+80,by,"---",g_clrText,8,"Segoe UI Bold"); by+=18;
   GUIRect(PREFIX+"DIV1",x+8,by,g_panelW-16,1,g_clrBorder,g_clrBorder); by+=6;
   // Trade stats
   GUILabel(PREFIX+"L_RECV",x+8,by,"Copied",g_clrDim,8);
   GUILabel(PREFIX+"VAL_RECV",x+80,by,"0",g_clrSafe,8,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_SENT2",x+8,by,"Sent",g_clrDim,8);
   GUILabel(PREFIX+"VAL_SENT",x+80,by,"0",g_clrText,8,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_SIG",x+8,by,"Signals",g_clrDim,8);
   GUILabel(PREFIX+"VAL_SIG",x+80,by,"0",g_clrText,8,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_PC",x+8,by,"Partials",g_clrDim,8);
   GUILabel(PREFIX+"V_PCLOSE",x+80,by,"0",g_clrText,8,"Segoe UI Bold"); by+=18;
   GUIRect(PREFIX+"DIV2",x+8,by,g_panelW-16,1,g_clrBorder,g_clrBorder); by+=6;
   // Account info
   GUILabel(PREFIX+"L_BAL2",x+8,by,"Balance",g_clrDim,8);
   GUILabel(PREFIX+"VAL_BAL",x+80,by,"---",g_clrSafe,8,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_EQ",x+8,by,"Equity",g_clrDim,8);
   GUILabel(PREFIX+"VAL_EQ",x+80,by,"---",g_clrSafe,8,"Segoe UI Bold"); by+=18;
   GUIRect(PREFIX+"DIV3",x+8,by,g_panelW-16,1,g_clrBorder,g_clrBorder); by+=6;
   // Symbol, Last Signal, Status, Filtered
   GUILabel(PREFIX+"L_SYM",x+8,by,"Symbol",g_clrDim,8);
   GUILabel(PREFIX+"VAL_SYM",x+80,by,_Symbol,g_clrText,8,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_LST",x+8,by,"Last Signal",g_clrDim,8);
   GUILabel(PREFIX+"VAL_LST",x+80,by,"None",g_clrText,8); by+=16;
   GUILabel(PREFIX+"L_ERR",x+8,by,"Status",g_clrDim,8);
   GUILabel(PREFIX+"VAL_ERR",x+80,by,"Ready",g_clrSafe,8,"Segoe UI Bold"); by+=16;
   GUILabel(PREFIX+"L_FIL",x+8,by,"Filtered",g_clrDim,8);
   GUILabel(PREFIX+"VAL_FILT",x+80,by,"None",g_clrDim,8); by+=18;
   GUIRect(PREFIX+"DIV4",x+8,by,g_panelW-16,1,g_clrBorder,g_clrBorder); by+=6;
   // ARM status
   GUILabel(PREFIX+"VAL_ARM",x+8,by,"[ON] ARMED",g_clrSafe,8,"Segoe UI Bold"); by+=22;
   // Buttons row
   GUIButton(PREFIX+"BTN_SETTINGS",x+4,by,g_panelW/2-6,26,"[=] SETTINGS",C'25,28,42',g_clrAccent);
   GUIButton(PREFIX+"BTN_MIN",x+g_panelW/2+2,by,g_panelW/2-6,26,"MINIMIZE",C'25,28,42',g_clrDim);
   by+=30;
   GUIButton(PREFIX+"BTN_TEST",x+4,by,g_panelW-8,26,"TEST CONNECTION",C'20,42,35',g_clrSafe);
   ChartRedraw();
}

string TCU_TimerSnapshot()
{
   UpdateModeStr();
   return IntegerToString(g_tcuTab) + "|" +
          IntegerToString((int)g_minimized) + "|" +
          IntegerToString((int)ArmExecution) + "|" +
          g_currentMode + "|" +
          IntegerToString(g_tradesSent) + "|" +
          IntegerToString(g_tradesReceived) + "|" +
          IntegerToString(PositionsTotal()) + "|" +
          DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "|" +
          g_lastSignal + "|" +
          g_lastError + "|" +
          g_lastFilterReason + "|" +
          IntegerToString(g_tcuNewsCount) + "|" +
          IntegerToString((int)EnableNewsPause);
}

void UpdatePanel()
{
   if(g_tcuClosed) return;
   if(g_tcuCanvasCreated || !g_tcuClosed)
   {
      // Timer updates should not repaint settings pages every 500ms; edit boxes
      // are native objects over the canvas and full redraws make them flicker.
      if(g_tcuTab != 0 && !g_minimized)
         return;

      string snap = TCU_TimerSnapshot();
      if(snap == g_tcuLastTimerSnapshot)
         return;
      g_tcuLastTimerSnapshot = snap;
      TCU_DrawUI();
      return;
   }

   UpdateModeStr();
   string arm=ArmExecution?"[ON] ARMED":"[OFF] DISARMED";
   if(ArmExecution&&PropFirmMode) arm+=" [PROP]";
   ObjectSetString(0,PREFIX+"VAL_ARM",OBJPROP_TEXT,arm);
   ObjectSetInteger(0,PREFIX+"VAL_ARM",OBJPROP_COLOR,ArmExecution?g_clrSafe:g_clrDanger);
   ObjectSetString(0,PREFIX+"VAL_MODE",OBJPROP_TEXT,g_currentMode);
   ObjectSetString(0,PREFIX+"VAL_RECV",OBJPROP_TEXT,IntegerToString(g_tradesReceived));
   ObjectSetString(0,PREFIX+"VAL_SENT",OBJPROP_TEXT,IntegerToString(g_tradesSent));
   ObjectSetString(0,PREFIX+"VAL_SIG",OBJPROP_TEXT,IntegerToString(g_signalsProcessed));
   ObjectSetString(0,PREFIX+"V_PCLOSE",OBJPROP_TEXT,IntegerToString(g_partialCount));
   ObjectSetString(0,PREFIX+"VAL_SYM",OBJPROP_TEXT,_Symbol);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE),eq=AccountInfoDouble(ACCOUNT_EQUITY);
   ObjectSetString(0,PREFIX+"VAL_BAL",OBJPROP_TEXT,"$"+DoubleToString(bal,2));
   ObjectSetString(0,PREFIX+"VAL_EQ",OBJPROP_TEXT,"$"+DoubleToString(eq,2));
   ObjectSetInteger(0,PREFIX+"VAL_EQ",OBJPROP_COLOR,eq>=bal?g_clrSafe:g_clrDanger);
   if(EnableBridgeMode){ string bv=g_bridgeFailCount==0?"ONLINE:"+IntegerToString(BridgePort):(g_bridgeFailCount>=3?"OFFLINE":"..."); color bc=g_bridgeFailCount==0?g_clrSafe:(g_bridgeFailCount>=3?g_clrDanger:g_clrWarn); ObjectSetString(0,PREFIX+"V_BRIDGE",OBJPROP_TEXT,bv); ObjectSetInteger(0,PREFIX+"V_BRIDGE",OBJPROP_COLOR,bc); }
   else { ObjectSetString(0,PREFIX+"V_BRIDGE",OBJPROP_TEXT,"OFF"); ObjectSetInteger(0,PREFIX+"V_BRIDGE",OBJPROP_COLOR,g_clrDim); }
   if(EnableBotAPIMode){ string tv=g_telegramFailCount==0&&g_botFirstPollDone?"ONLINE":(g_telegramFailCount>=3?"FAIL":"..."); color tc2=g_telegramFailCount==0&&g_botFirstPollDone?g_clrSafe:(g_telegramFailCount>=3?g_clrDanger:g_clrWarn); ObjectSetString(0,PREFIX+"V_TG",OBJPROP_TEXT,tv); ObjectSetInteger(0,PREFIX+"V_TG",OBJPROP_COLOR,tc2); }
   else { ObjectSetString(0,PREFIX+"V_TG",OBJPROP_TEXT,"OFF"); ObjectSetInteger(0,PREFIX+"V_TG",OBJPROP_COLOR,g_clrDim); }
   string sd=g_lastSignal; if(StringLen(sd)>22) sd=StringSubstr(sd,0,22)+"..";
   ObjectSetString(0,PREFIX+"VAL_LST",OBJPROP_TEXT,StringLen(sd)>0?sd:"None");
   if(StringLen(g_lastError)>0){ ObjectSetString(0,PREFIX+"VAL_ERR",OBJPROP_TEXT,g_lastError); ObjectSetInteger(0,PREFIX+"VAL_ERR",OBJPROP_COLOR,g_clrDanger); }
   else { ObjectSetString(0,PREFIX+"VAL_ERR",OBJPROP_TEXT,"Ready"); ObjectSetInteger(0,PREFIX+"VAL_ERR",OBJPROP_COLOR,g_clrSafe); }
   if(StringLen(g_lastFilterReason)>0){ string fd=g_lastFilterReason; if(StringLen(fd)>20) fd=StringSubstr(fd,0,20)+".."; ObjectSetString(0,PREFIX+"VAL_FILT",OBJPROP_TEXT,fd); ObjectSetInteger(0,PREFIX+"VAL_FILT",OBJPROP_COLOR,g_clrWarn); }
   else { ObjectSetString(0,PREFIX+"VAL_FILT",OBJPROP_TEXT,"None"); ObjectSetInteger(0,PREFIX+"VAL_FILT",OBJPROP_COLOR,g_clrDim); }
   ChartRedraw();
}


//+==================================================================+
//| GUI HELPERS (Matching NTS Suite)                                  |
//+==================================================================+
void GUIRect(string n, int x, int y, int w, int h, color bg, color brd)
{
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      brd);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,     0);
}

void GUILabel(string n, int x, int y, string txt, color clr, int sz=8, string font="Segoe UI")
{
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetString (0, n, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetString (0, n, OBJPROP_FONT,       font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   sz);
   ObjectSetInteger(0, n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,     2);
}

void GUIButton(string n, int x, int y, int w, int h, string txt, color bg, color tc)
{
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,      h);
   ObjectSetString (0, n, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      tc);
   ObjectSetString (0, n, OBJPROP_FONT,       "Segoe UI Bold");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   9);
   ObjectSetInteger(0, n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,     3);
   ObjectSetInteger(0, n, OBJPROP_STATE,      false);
}
//+------------------------------------------------------------------+


