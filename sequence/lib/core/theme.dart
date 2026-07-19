import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sequence Design Language — token layer.
///
/// A calm, tactile system for a digital Sequence board: a quiet cool-neutral
/// surface, with all saturation reserved for the team chips and the live-turn
/// accent. Every value here mirrors the design spec so the build matches it.

// ── Neutrals & surface ──────────────────────────────────────────────────────
const Color kInk = Color(0xFF1D2129); // headings, ranks
const Color kStrong = Color(0xFF3A4150);
const Color kBody = Color(0xFF5A626F); // body copy
const Color kMuted = Color(0xFF8A93A3);
const Color kLabel = Color(0xFFAAB2C0); // eyebrows, faint labels
const Color kLine = Color(0xFFE1E4EA); // hairline borders
const Color kPanelMuted = Color(0xFFF6F7F9);
const Color kSurface = Color(0xFFFFFFFF);
const Color kCanvasTop = Color(0xFFF4F6FA);
const Color kCanvasBottom = Color(0xFFE7EBF2);
const Color kGold = Color(0xFFF3B13B); // accent

// Card ink + the slate of a board cell border / free corner.
const Color kCardRed = Color(0xFFD8453B); // ♥ ♦
const Color kCardBlack = Color(0xFF272B34); // ♠ ♣
const Color kCellBorder = Color(0xFFE6E8EE);
const Color kCornerTop = Color(0xFFEDF0F5);
const Color kCornerBottom = Color(0xFFE0E5EE);

/// The page background gradient (radial, light → slightly cooler).
const RadialGradient kCanvasGradient = RadialGradient(
  center: Alignment(0, -1),
  radius: 1.2,
  colors: [kCanvasTop, kCanvasBottom],
);

// ── Teams ───────────────────────────────────────────────────────────────────
// One oklch lightness/chroma, hue-rotated. Order follows the official rules
// (2 teams = blue + green; red is the 3rd team). Each ships with a 12% "soft"
// tint for active rows and washes.
const List<Color> kTeamColors = <Color>[
  Color(0xFF2F6DF0), // blue
  Color(0xFF16A36B), // green
  Color(0xFFD8453B), // red
];
const List<Color> kTeamSoftColors = <Color>[
  Color(0xFFE0E9FC), // blue soft
  Color(0xFFDCF2E8), // green soft
  Color(0xFFFBE4E1), // red soft
];
const List<String> kTeamNames = <String>['Blue', 'Green', 'Red'];

/// Const alias of the blue team color, for use as a default parameter value
/// (list indexing into [kTeamColors] is not a compile-time constant).
const Color kAccentDefault = Color(0xFF2F6DF0);

Color teamColor(int team) => kTeamColors[team % kTeamColors.length];
Color teamSoft(int team) => kTeamSoftColors[team % kTeamSoftColors.length];
String teamName(int team) => kTeamNames[team % kTeamNames.length];

// ── Radius ──────────────────────────────────────────────────────────────────
const double kRadiusCell = 7;
const double kRadiusCard = 9;
const double kRadiusPanel = 16;
const double kRadiusControl = 14;

// ── Elevation ───────────────────────────────────────────────────────────────
const List<BoxShadow> kControlShadow = [
  BoxShadow(color: Color(0x0F141823), blurRadius: 18, offset: Offset(0, 6)),
];
const List<BoxShadow> kPanelShadow = [
  BoxShadow(color: Color(0x0F141823), blurRadius: 40, offset: Offset(0, 16)),
];
const List<BoxShadow> kCardShadow = [
  BoxShadow(color: Color(0x26141823), blurRadius: 18, offset: Offset(0, 8)),
];

// ── Motion ──────────────────────────────────────────────────────────────────
/// Springy landing for chips/cards and modal entrances.
const Cubic kEaseDrop = Cubic(0.2, 0.9, 0.25, 1.15);

/// Gentle ease for hover lift / selection.
const Cubic kEaseSoft = Cubic(0.2, 0.8, 0.3, 1);

// ── Typography helpers ──────────────────────────────────────────────────────
/// Archivo — wordmark, titles, ranks, buttons, team names.
TextStyle archivo({
  double? size,
  FontWeight weight = FontWeight.w700,
  Color? color,
  double? spacing,
  double? height,
}) =>
    GoogleFonts.archivo(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
    );

/// Space Mono — eyebrows, badges (DEAD / WILD / REMOVE / TURN), token labels.
TextStyle mono({
  double? size,
  FontWeight weight = FontWeight.w700,
  Color? color,
  double? spacing,
}) =>
    GoogleFonts.spaceMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
    );

/// Uppercase mono eyebrow label.
TextStyle eyebrow({Color color = kLabel, double size = 11}) =>
    mono(size: size, weight: FontWeight.w700, color: color, spacing: 2);

// ── ThemeData ───────────────────────────────────────────────────────────────
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kTeamColors[0],
    brightness: Brightness.light,
    surface: kSurface,
  );

  TextTheme t = ThemeData.light().textTheme;
  final text = t.copyWith(
    displayLarge: archivo(weight: FontWeight.w800, color: kInk, height: 1),
    displayMedium: archivo(weight: FontWeight.w800, color: kInk, height: 1),
    displaySmall: archivo(weight: FontWeight.w800, color: kInk, height: 1.05),
    headlineMedium: archivo(weight: FontWeight.w800, color: kInk),
    headlineSmall: archivo(weight: FontWeight.w800, color: kInk),
    titleLarge: archivo(weight: FontWeight.w700, color: kInk),
    titleMedium: archivo(weight: FontWeight.w700, color: kInk),
    titleSmall: archivo(weight: FontWeight.w600, color: kStrong),
    bodyLarge: TextStyle(color: kBody, fontSize: 16, height: 1.55),
    bodyMedium: TextStyle(color: kBody, fontSize: 14, height: 1.55),
    bodySmall: TextStyle(color: kMuted, fontSize: 12, height: 1.5),
    labelLarge: archivo(weight: FontWeight.w700, color: kStrong, size: 14),
    labelMedium: mono(size: 11, color: kMuted, spacing: 1),
    labelSmall: mono(size: 10, color: kLabel, spacing: 1),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      surface: kSurface,
      onSurface: kInk,
      primary: kTeamColors[0],
      outline: kLine,
    ),
    scaffoldBackgroundColor: kCanvasTop,
    textTheme: text,
    dividerTheme: const DividerThemeData(color: kLine, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: kCanvasTop,
      surfaceTintColor: Colors.transparent,
      foregroundColor: kInk,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: archivo(weight: FontWeight.w800, color: kInk, size: 20),
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusPanel),
        side: const BorderSide(color: kLine),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kInk,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusControl),
        ),
        textStyle: archivo(weight: FontWeight.w700, size: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: const BorderSide(color: kLine),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusControl),
        ),
        textStyle: archivo(weight: FontWeight.w700, size: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kTeamColors[0],
        textStyle: archivo(weight: FontWeight.w700, size: 14),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(archivo(weight: FontWeight.w700, size: 14)),
        side: const WidgetStatePropertyAll(BorderSide(color: kLine)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kPanelMuted,
      labelStyle: const TextStyle(color: kMuted),
      hintStyle: const TextStyle(color: kLabel),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: const BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: BorderSide(color: kTeamColors[0], width: 2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: const BorderSide(color: kLine),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusPanel),
      ),
      titleTextStyle: archivo(weight: FontWeight.w800, color: kInk, size: 20),
      contentTextStyle: const TextStyle(color: kBody, fontSize: 15, height: 1.5),
    ),
  );
}

/// A reusable calm canvas gradient background. Wrap a screen body with this to
/// get the design's soft radial surface behind transparent scaffolds.
class CanvasBackground extends StatelessWidget {
  final Widget child;
  const CanvasBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: kCanvasGradient),
      child: child,
    );
  }
}

/// A small poker chip used decoratively (the three team dots beside the
/// wordmark). [filled] draws the disc; otherwise just the dashed ring.
class TeamDot extends StatelessWidget {
  final int team;
  final double size;
  const TeamDot({super.key, required this.team, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: teamColor(team), shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(size * 0.23),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.55), width: size * 0.07),
          ),
        ),
      ),
    );
  }
}

/// The SEQUENCE wordmark: three team chips over the spaced Archivo logotype and
/// an optional mono eyebrow.
class Wordmark extends StatelessWidget {
  final double size;
  final String? eyebrow;
  const Wordmark({super.key, this.size = 38, this.eyebrow});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var t = 0; t < 3; t++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: TeamDot(team: t, size: size * 0.62),
              ),
          ],
        ),
        SizedBox(height: size * 0.4),
        Text('SEQUENCE',
            style: archivo(
                weight: FontWeight.w800,
                color: kInk,
                size: size,
                spacing: size * 0.22,
                height: 1)),
        if (eyebrow != null) ...[
          SizedBox(height: size * 0.22),
          Text(eyebrow!.toUpperCase(),
              style: mono(size: 11, color: kLabel, spacing: 4)),
        ],
      ],
    );
  }
}
