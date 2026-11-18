import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../player/playback_queue.dart';
import '../library/catalog_view_model.dart';
import '../library/library_view_model.dart';
import 'backup_view_model.dart';

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => BackupViewModel(
      context.read<PlaybackQueue>(),
      reloadViews: () async {
        final catalog = context.read<CatalogViewModel>();
        final library = context.read<LibraryViewModel>();
        await catalog.waitUntilIdle();
        catalog.query = '';
        catalog.publisher = null;
        await catalog.load();
        await library.load();
        if (catalog.error != null || library.errorMessage != null) {
          throw StateError('restore view reload failed');
        }
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      },
    ),
    child: const _BackupBody(),
  );
}

class _BackupBody extends StatelessWidget {
  const _BackupBody();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BackupViewModel>();
    return PopScope(
      canPop: !vm.busy && !vm.requiresRestart,
      child: Scaffold(
        appBar: AppBar(title: const Text('백업 파일')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.inventory_2_outlined, size: 56),
              const SizedBox(height: 20),
              Text(
                '우리 책과 목소리를 보관해요',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                '책·사진·녹음·플레이리스트·만들던 책·읽던 위치를 한 파일로 저장해요. 백업 중에는 재생을 멈춰요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '백업 파일에는 가족의 사진과 목소리가 포함돼요. 암호화되지 않으니 개인 저장소에 보관해 주세요.',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: vm.busy || vm.requiresRestart || !Platform.isAndroid
                    ? null
                    : () => vm.run(true),
                icon: const Icon(Icons.save_alt),
                label: const Text('백업 파일 저장'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: vm.busy || vm.requiresRestart || !Platform.isAndroid
                    ? null
                    : () => vm.run(false),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('백업 파일 검사'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: vm.busy || vm.requiresRestart || !Platform.isAndroid
                    ? null
                    : () => vm.restore((preview) async {
                        if (!context.mounted) return false;
                        return await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('이 백업으로 책장을 바꿀까요?'),
                                content: Text(
                                  '책 ${preview.books}권 · 플레이리스트 ${preview.playlists}개 · 만들던 책 ${preview.drafts}권\n\n현재 책장과 플레이리스트, 최근재생목록을 백업 내용으로 교체해요. 합쳐지지 않아요. 보관할 현재 자료가 있다면 취소하고 먼저 백업해 주세요.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('취소'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('책장 교체'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                      }),
                icon: const Icon(Icons.restore),
                label: const Text('백업으로 책장 복원'),
              ),
              const SizedBox(height: 12),
              const Text(
                '복원은 백업을 검사한 뒤 교체할 내용을 확인하고 진행해요. 검사만 하면 현재 책장은 바뀌지 않아요.',
              ),
              if (!Platform.isAndroid)
                const Text('파일 저장·선택은 현재 Android에서 지원해요.'),
              if (vm.busy) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(vm.status),
              ],
              if (vm.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(vm.message!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
