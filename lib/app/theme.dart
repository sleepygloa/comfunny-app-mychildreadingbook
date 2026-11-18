import 'package:flutter/material.dart';

/// 앱 테마. **아이가 직접 만지는 화면**이라는 전제로 만든다.
///
/// 설계 근거 ([1_DESIGN §1.7] 접근성):
/// - **큰 터치 타깃** — 아이 손가락은 정확하지 않다. 최소 56dp (Material 기본은 48dp)
/// - **높은 대비** — 밝은 곳(거실·차 안)에서도 읽힌다
/// - **큰 글자** — 보호자도 아이도 읽는다
/// - 차분한 색 — 자기 전에 보는 화면이라 형광색을 쓰지 않는다
class AppTheme {
  AppTheme._();

  /// 아이 손가락 기준 최소 터치 크기. Material 기본(48)보다 크다.
  static const double minTouchSize = 56.0;

  /// 책장 카드 최소 높이.
  static const double cardMinHeight = 96.0;

  /// 따뜻한 종이색 계열 — 책을 읽는 앱이라는 정서.
  static const Color _seed = Color(0xFF6350A0);

  static ThemeData light() => _build(Brightness.light);

  /// 다크 테마를 함께 만드는 이유: **자기 전에 쓰는 앱**이다. 밝은 화면은 눈을 피곤하게 한다.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final astra = scheme.copyWith(
      primary: Color(isDark ? 0xFFD1C2FF : 0xFF6350A0),
      onPrimary: Color(isDark ? 0xFF241B3D : 0xFFFFFFFF),
      surface: Color(isDark ? 0xFF191D2B : 0xFFFFF9F0),
      secondary: Color(isDark ? 0xFFB6DACA : 0xFF3D705F),
      secondaryContainer: Color(isDark ? 0xFF2E4941 : 0xFFDBEEE3),
      onSecondaryContainer: Color(isDark ? 0xFFD9F0E4 : 0xFF284E40),
      primaryContainer: Color(isDark ? 0xFF45365C : 0xFFECE0FA),
      onPrimaryContainer: Color(isDark ? 0xFFF2E5FF : 0xFF4B3568),
      onSurface: Color(isDark ? 0xFFF6F1E7 : 0xFF282B3A),
      onSurfaceVariant: Color(isDark ? 0xFFB9BFCE : 0xFF626477),
      surfaceContainerLow: Color(isDark ? 0xFF252B3D : 0xFFFFFEFA),
    );
    final base = ThemeData(colorScheme: astra, useMaterial3: true);

    return base.copyWith(
      // 터치 타깃을 전역으로 키운다 — 화면마다 지정하는 것을 잊지 않게.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.comfortable,

      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),

      // 본문 글자를 기본보다 키운다.
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 17,
          height: 1.5,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 15,
          height: 1.5,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchSize * 2, minTouchSize),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouchSize * 2, minTouchSize),
          textStyle: base.textTheme.labelLarge?.copyWith(fontSize: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTouchSize, minTouchSize),
          iconSize: 28,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: const Color(0xFF765361).withValues(alpha: .12),
        color: astra.surfaceContainerLow,
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: astra.surfaceContainerLow,
        indicatorColor: astra.primaryContainer,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: astra.onSurface,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: astra.surfaceContainerLow,
        selectedColor: astra.primaryContainer,
        shape: const StadiumBorder(),
        side: BorderSide(color: astra.primary.withValues(alpha: .22)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C3C) : const Color(0xFFF3EEE8),
        // 입력 필드도 손가락으로 눌러야 한다.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),

      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 14,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
