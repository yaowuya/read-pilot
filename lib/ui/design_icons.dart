import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Lucide mappings from `docs/阅读助手_完整设计稿.html` icon names.
///
/// Screens use these fields instead of importing [LucideIcons]. A comment
/// names the design glyph. "closest" means that exact name is not used on
/// the screen, so a nearby Lucide icon stands in.
///
/// Tab and reader-tool aliases keep the glyphs already shipped.
abstract final class DesignIcons {
  static const arrowDown = LucideIcons.arrowDown; // closest; reorder pair
  static const arrowUp = LucideIcons.arrowUp; // ArrowUp
  static const arrowUpDown = LucideIcons.arrowUpDown; // closest; no sort glyph
  static const arrowUpRight = LucideIcons.arrowUpRight; // ArrowUpRight
  static const audioLines = LucideIcons.audioLines; // AudioLines
  static const bookOpen = LucideIcons.bookOpen; // BookOpen
  static const bookmark = LucideIcons.bookmark; // Bookmark
  static const bookmarkCheck = LucideIcons.bookmarkCheck; // BookmarkCheck
  static const chart = LucideIcons.chartNoAxesColumn; // ChartNoAxesColumn
  static const check = LucideIcons.check; // Check
  static const chevronDown = LucideIcons.chevronDown; // ChevronDown
  static const chevronLeft = LucideIcons.chevronLeft; // ChevronLeft
  static const chevronRight = LucideIcons.chevronRight; // ChevronRight
  static const chevronUp = LucideIcons.chevronUp; // ChevronUp
  static const circle = LucideIcons.circle; // closest hollow mark
  static const circleAlert = LucideIcons.circleAlert; // CircleAlert
  static const circleCheck = LucideIcons.circleCheck; // CircleCheck
  static const circleHelp = LucideIcons.circleHelp; // CircleHelp
  static const close = LucideIcons.x; // X
  static const cloud = LucideIcons.cloud; // Cloud
  static const cloudOff = LucideIcons.cloudOff; // CloudOff
  static const copy = LucideIcons.copy; // Copy
  static const download = LucideIcons.download; // Download
  static const ellipsis = LucideIcons.ellipsis; // Ellipsis
  static const eraser = LucideIcons.eraser; // Eraser
  static const fileJson = LucideIcons.fileJson; // FileJson
  static const fileText = LucideIcons.fileText; // FileText
  static const fileUp = LucideIcons.fileUp; // FileUp
  static const folderOpen = LucideIcons.folderOpen; // FolderOpen
  static const globe = LucideIcons.globe; // Globe
  static const hardDrive = LucideIcons.hardDrive; // HardDrive
  static const highlighter = LucideIcons.highlighter; // Highlighter
  static const info = LucideIcons.info; // Info
  static const layers = LucideIcons.layers2; // Layers2
  static const libraryBig = LucideIcons.libraryBig; // LibraryBig
  static const linkOff = LucideIcons.link2Off; // closest broken link
  static const list = LucideIcons.list; // List
  static const listChecks = LucideIcons.listChecks; // closest multi-select
  static const locateFixed = LucideIcons.locateFixed; // LocateFixed
  static const moon = LucideIcons.moon; // Moon
  static const notebookPen = LucideIcons.notebookPen; // NotebookPen
  static const pause = LucideIcons.pause; // Pause
  static const play = LucideIcons.play; // Play
  static const plus = LucideIcons.plus; // Plus
  static const refresh = LucideIcons.refreshCw; // RefreshCw
  static const rotateCcw = LucideIcons.rotateCcw; // RotateCcw
  static const scanSearch = LucideIcons.scanSearch; // closest; 刷新封面
  static const search = LucideIcons.search; // Search
  static const searchX = LucideIcons.searchX; // closest empty search
  static const settings = LucideIcons.settings2; // Settings2
  static const share = LucideIcons.share2; // Share2
  static const shieldCheck = LucideIcons.shieldCheck; // ShieldCheck
  static const sliders = LucideIcons.slidersHorizontal; // SlidersHorizontal
  static const sparkles = LucideIcons.sparkles; // Sparkles
  static const stopCircle = LucideIcons.stopCircle; // closest stop control
  static const sun = LucideIcons.sun; // Sun
  static const sunDim = LucideIcons.sunDim; // SunDim
  static const timer = LucideIcons.timer; // closest; 自动翻页
  static const trash = LucideIcons.trash2; // Trash2
  static const type = LucideIcons.type; // Type
  static const volume = LucideIcons.volume2; // Volume2
  static const wifi = LucideIcons.wifi; // Wifi

  static const tabShelf = LucideIcons.bookOpen;
  static const tabDiscover = LucideIcons.compass;
  static const tabProfile = LucideIcons.user;

  static const readerBack = LucideIcons.chevronLeft;
  static const readerBookmark = LucideIcons.bookmark;
  static const readerMore = LucideIcons.moreHorizontal;

  static const toolToc = LucideIcons.list;
  static const toolSource = LucideIcons.refreshCw;
  static const toolNotes = LucideIcons.pencil;
  static const toolSettings = LucideIcons.type;

  static const selectionHighlight = LucideIcons.highlighter;
  static const selectionNotes = LucideIcons.pencil;
  static const selectionExplain = LucideIcons.sparkles;
  static const selectionCopy = LucideIcons.copy;

  static const sheetDownload = LucideIcons.download;
  static const sheetSearch = LucideIcons.search;
  static const sheetMarkDone = LucideIcons.checkCircle;
}
