import 'package:flutter/material.dart';

/// 화면 상단 오류 배너.
///
/// 왜 SnackBar 가 아닌가: SnackBar 는 몇 초 뒤 사라진다. 저장 실패처럼 **사용자가
/// 행동해야 하는 오류**는 화면에 남아 있어야 한다. 일시적 알림(저장 성공)은 SnackBar 를 쓴다.
///
/// 왜 공통으로 뺐나: 책장·편집·에디터·플레이어가 모두 같은 형태의 오류를 보여준다.
/// 화면마다 복사하면 문구·색·닫기 동작이 갈라진다.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({required this.message, this.onClose, super.key});

  final String message;

  /// `null` 이면 닫기 버튼을 숨긴다 (닫을 수 없는 오류).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (onClose != null)
            TextButton(onPressed: onClose, child: const Text('닫기')),
        ],
      ),
    );
  }
}
