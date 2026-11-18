import '../settings/backup_screen.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/local/media_storage.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/repositories/book_authoring_repository.dart';
import '../../domain/repositories/reading_workspace_repositories.dart';
import '../../service_locator.dart';
import '../library/catalog_view_model.dart';
import '../common/parent_boundary.dart';
import '../common/storybook_widgets.dart';
import '../player/playback_queue.dart';
import '../player/queue_panel.dart';
import '../player/floating_player.dart';

Future<bool> confirmManagement(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('부모님과 함께 관리해요'),
        content: const Text('책과 플레이리스트를 변경하는 메뉴예요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('계속하기'),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> askTitle(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '이름'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(ctx, controller.text.trim());
            }
          },
          child: const Text('저장'),
        ),
      ],
    ),
  );
  // 다이얼로그 닫힘 애니메이션 동안 입력 위젯이 컨트롤러를 참조한다.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}

class LibraryShell extends StatefulWidget {
  const LibraryShell({super.key});
  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell> {
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CatalogViewModel>().load();
    });
  }

  Future<void> _newBook({String? seriesId}) async {
    await context.read<PlaybackQueue>().pause();
    if (!mounted) return;
    await context.push(
      seriesId == null ? '/content/new' : '/content/new?series=$seriesId',
    );
    if (mounted) await context.read<CatalogViewModel>().load();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: Text(['작은 도서관', '플레이리스트', '최근재생목록', '설정'][_tab]),
        actions: [
          if (_tab < 2)
            IconButton(
              tooltip: _tab == 0 ? '책 등록' : '플레이리스트 만들기',
              icon: const Icon(Icons.add),
              onPressed: catalog.isBusy
                  ? null
                  : () async {
                      if (_tab == 0) {
                        await _newBook();
                        return;
                      }
                      if (!await confirmManagement(context) ||
                          !context.mounted) {
                        return;
                      }
                      final title = await askTitle(context, '플레이리스트 만들기');
                      if (title != null) await catalog.createList(title);
                    },
            ),
          if (_tab == 0)
            PopupMenuButton<String>(
              tooltip: '책장 메뉴',
              onSelected: (value) async {
                if (value == 'new') {
                  await _newBook();
                } else {
                  if (!mounted) return;
                  await context.read<PlaybackQueue>().pause();
                  if (!context.mounted) return;
                  await context.push('/drafts');
                  if (mounted) await catalog.load();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'new', child: Text('책 등록')),
                PopupMenuItem(
                  value: 'drafts',
                  child: Text('만들던 책 (${catalog.draftList.length})'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (catalog.isBusy) const LinearProgressIndicator(),
            if (catalog.error != null)
              MaterialBanner(
                content: Text(catalog.error!),
                actions: [
                  TextButton(
                    onPressed: catalog.load,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _books(catalog),
                  _playlists(catalog),
                  const QueuePanel(),
                  const _Settings(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FloatingPlayer(),
          NavigationBar(
            animationDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: StoryTabIcon(
                  icon: Icons.auto_stories_outlined,
                  selected: false,
                ),
                selectedIcon: StoryTabIcon(
                  icon: Icons.auto_stories,
                  selected: true,
                ),
                label: '책장',
              ),
              NavigationDestination(
                icon: StoryTabIcon(
                  icon: Icons.library_music_outlined,
                  selected: false,
                ),
                selectedIcon: StoryTabIcon(
                  icon: Icons.library_music,
                  selected: true,
                ),
                label: '플레이리스트',
              ),
              NavigationDestination(
                icon: StoryTabIcon(
                  icon: Icons.history_outlined,
                  selected: false,
                ),
                selectedIcon: StoryTabIcon(icon: Icons.history, selected: true),
                label: '최근재생목록',
              ),
              NavigationDestination(
                icon: StoryTabIcon(
                  icon: Icons.settings_outlined,
                  selected: false,
                ),
                selectedIcon: StoryTabIcon(
                  icon: Icons.settings,
                  selected: true,
                ),
                label: '설정',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _books(CatalogViewModel c) => RefreshIndicator(
    onRefresh: c.load,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        StoryWelcome(
          title: '오늘은 어떤 책을\n함께 읽을까요?',
          subtitle: c.books.isEmpty
              ? '한 권의 책에, 다정한 목소리를 담아요.'
              : '${c.books.length}권의 이야기가 기다리고 있어요.',
        ),
        _SearchAndBadges(catalog: c),
        if (c.books.isEmpty)
          const _Empty(
            icon: Icons.auto_stories_outlined,
            title: '첫 이야기를 기다리고 있어요',
            detail: '오른쪽 위 + 버튼으로 책을 등록해 주세요.',
          ),
        if (c.books.isNotEmpty)
          BookTree(
            books: c.filter(c.books),
            onAddSeries: (id) => _newBook(seriesId: id),
          ),
      ],
    ),
  );
  Widget _playlists(CatalogViewModel c) => RefreshIndicator(
    onRefresh: c.load,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        StoryWelcome(
          title: '좋아하는 이야기,\n차곡차곡 모아요',
          subtitle: '잠들기 전에도, 함께 웃고 싶은 날에도.',
          isPlaylist: true,
        ),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '플레이리스트 검색',
          ),
          onChanged: (s) => setState(() => _playlistSearch = s),
        ),
        const SizedBox(height: 16),
        if (c.lists.isEmpty)
          const _Empty(
            icon: Icons.playlist_add,
            title: '나만의 목록을 만들어 보세요',
            detail: '잠들기 전, 좋아하는 이야기처럼 모아둘 수 있어요.',
          ),
        for (final list in c.lists.where(
          (p) => p.title.toLowerCase().contains(_playlistSearch.toLowerCase()),
        ))
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              leading: const BookFriend(size: 58, color: Color(0xFFADCFC4)),
              title: Text(list.title),
              subtitle: Text('${c.booksFor(list).length}권'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PlaylistDetail(id: list.id),
                ),
              ),
              trailing: IconButton(
                tooltip: '${list.title} 전체 재생',
                icon: const Icon(Icons.play_circle_outline),
                onPressed: c.booksFor(list).isEmpty
                    ? null
                    : () => playBooks(context, c.booksFor(list)),
              ),
            ),
          ),
      ],
    ),
  );
  String _playlistSearch = '';
}

Future<void> playBooks(BuildContext context, List<Content> books) async {
  final queue = context.read<PlaybackQueue>();
  if (!books.any((b) => b.isPlayable)) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('재생할 페이지가 있는 책이 없어요.')));
    return;
  }
  await queue.playAll(books);
}

class _SearchAndBadges extends StatefulWidget {
  const _SearchAndBadges({required this.catalog});
  final CatalogViewModel catalog;
  @override
  State<_SearchAndBadges> createState() => _SearchAndBadgesState();
}

class _SearchAndBadgesState extends State<_SearchAndBadges> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.catalog.query,
  );
  CatalogViewModel get catalog => widget.catalog;
  @override
  void didUpdateWidget(covariant _SearchAndBadges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != catalog.query) {
      _controller.value = TextEditingValue(
        text: catalog.query,
        selection: TextSelection.collapsed(offset: catalog.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        controller: _controller,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: '출판사 · 전집 · 책 제목 검색',
        ),
        onChanged: catalog.search,
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('전체'),
                selected: catalog.publisher == null,
                onSelected: (_) => catalog.selectPublisher(null),
              ),
            ),
            for (final publisher in catalog.publishers)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(publisher),
                  selected: catalog.publisher == publisher,
                  onSelected: (_) => catalog.selectPublisher(
                    catalog.publisher == publisher ? null : publisher,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ],
  );
}

/// 검색 결과를 펼치되 평소 펼침 상태는 PageStorage에 유지한다.
class BookTree extends StatelessWidget {
  const BookTree({super.key, required this.books, this.onAddSeries});
  final List<Content> books;
  final void Function(String)? onAddSeries;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<CatalogViewModel>();
    final groups = <String, Map<String, List<Content>>>{};
    for (final b in books) {
      groups
          .putIfAbsent(c.publisherOf(b), () => {})
          .putIfAbsent(b.seriesId ?? '', () => [])
          .add(b);
    }
    if (books.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('조건에 맞는 책이 없어요.'),
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => playBooks(context, books),
            icon: const Icon(Icons.play_arrow),
            label: Text('전체 재생 (${books.length}권)'),
          ),
        ),
        for (final pub in groups.entries)
          Card(
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
                  ? AnimationStyle.noAnimation
                  : const AnimationStyle(
                      duration: Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                    ),
              key: PageStorageKey('publisher-${pub.key}-${c.query.isNotEmpty}'),
              initiallyExpanded: true,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.cottage_outlined,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
              title: Text(
                pub.key,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${pub.value.values.expand((v) => v).length}권'),
              children: [
                for (final series in pub.value.entries)
                  ExpansionTile(
                    expansionAnimationStyle:
                        MediaQuery.disableAnimationsOf(context)
                        ? AnimationStyle.noAnimation
                        : const AnimationStyle(
                            duration: Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                          ),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    key: PageStorageKey(
                      'series-${pub.key}-${series.key}-${c.query}',
                    ),
                    initiallyExpanded: c.query.isNotEmpty,
                    leading: const Icon(Icons.collections_bookmark_outlined),
                    title: Text(c.seriesTitle(series.value.first)),
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () => playBooks(context, series.value),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('전집 재생'),
                          ),
                          if (onAddSeries != null && series.key.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => onAddSeries!(series.key),
                              icon: const Icon(Icons.add),
                              label: const Text('이 전집에 책 추가'),
                            ),
                        ],
                      ),
                      for (final book in series.value) BookRow(book: book),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class BookRow extends StatelessWidget {
  const BookRow({super.key, required this.book});
  final Content book;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: BookCover(book: book),
    title: Text(
      '${book.volume == null ? '' : '${book.volume}. '}${book.title}',
    ),
    subtitle: Text('${book.pageCount}쪽'),
    onTap: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .7,
          child: Column(
            children: [
              ListTile(
                title: Text(book.title),
                subtitle: Text('${book.pageCount}쪽'),
                trailing: IconButton(
                  tooltip: '책 재생',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () {
                    Navigator.pop(ctx);
                    playBooks(context, [book]);
                  },
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final page in book.orderedPages)
                      ListTile(
                        leading: Text('${page.orderIndex + 1}'),
                        title: Text(page.hasText ? page.text! : '그림과 목소리'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    trailing: PopupMenuButton<String>(
      tooltip: '${book.title} 메뉴',
      onSelected: (action) => _action(context, action),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'play', child: Text('재생')),
        PopupMenuItem(value: 'queue', child: Text('최근재생목록에 추가')),
        PopupMenuItem(value: 'playlist', child: Text('플레이리스트에 추가')),
        PopupMenuItem(value: 'edit', child: Text('책 수정')),
        PopupMenuItem(value: 'voice', child: Text('목소리 넣기')),
        PopupMenuItem(value: 'delete', child: Text('책 삭제')),
      ],
    ),
  );
  Future<void> _action(BuildContext context, String action) async {
    final c = context.read<CatalogViewModel>();
    final q = context.read<PlaybackQueue>();
    if (action == 'play') {
      await playBooks(context, [book]);
      return;
    }
    if (action == 'queue') {
      await q.append([book]);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('최근재생목록에 추가했어요.')));
      }
      return;
    }
    if (action == 'edit' || action == 'voice') {
      await q.pause();
      if (!context.mounted) return;
      await context.push(
        '/content/${book.id}/${action == 'voice' ? 'voice' : 'edit'}',
      );
      await c.load();
      return;
    }
    if (!await confirmManagement(context) || !context.mounted) return;
    if (action == 'playlist') {
      final selected = await showDialog<Playlist>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('담을 플레이리스트'),
          children: [
            if (c.lists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('플레이리스트 탭의 + 버튼으로 먼저 만들어 주세요.'),
              ),
            for (final p in c.lists)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: Text(p.title),
              ),
          ],
        ),
      );
      if (selected != null) {
        await c.saveList(
          selected.copyWith(
            contentIds: {...selected.contentIds, book.id}.toList(),
          ),
        );
      }
    } else if (action == 'delete') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${book.title} 삭제'),
          content: const Text('이 책의 사진과 녹음도 삭제돼요. 되돌릴 수 없어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (yes == true) {
        await c.mutate(() async {
          await q.remove(book.id);
          await sl<BookAuthoringRepository>().discard(book.id);
          await sl<ReadingPositionRepository>().delete(book.id);
          await c.contents.delete(book.id);
        });
      }
    }
  }
}

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});
  final Content book;
  @override
  Widget build(BuildContext context) {
    final path = book.coverPath ?? book.pages.firstOrNull?.imagePath;
    final fallback = Container(
      width: 44,
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const BookFriend(size: 44),
    );
    return path == null
        ? fallback
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(sl<MediaStorage>().absolutePathOf(book.id, path)),
              width: 44,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
          );
  }
}

class PlaylistDetail extends StatelessWidget {
  const PlaylistDetail({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<CatalogViewModel>();
    final p = c.lists.where((p) => p.id == id).firstOrNull;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('플레이리스트')),
        body: const Center(child: Text('삭제된 플레이리스트예요.')),
      );
    }
    final books = c.booksFor(p);
    return Scaffold(
      appBar: AppBar(
        title: Text(p.title),
        actions: [
          PopupMenuButton<String>(
            tooltip: '플레이리스트 관리',
            onSelected: (action) async {
              if (!await confirmManagement(context) || !context.mounted) return;
              if (action == 'rename') {
                final title = await askTitle(
                  context,
                  '이름 변경',
                  initial: p.title,
                );
                if (title != null) await c.saveList(p.copyWith(title: title));
              }
              if (action == 'edit' && context.mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ParentBoundary(
                      initiallyConfirmed: true,
                      child: PlaylistEditor(playlist: p),
                    ),
                  ),
                );
              }
              if (action == 'delete' && context.mounted) {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('플레이리스트를 삭제할까요?'),
                    content: const Text('책장에 등록한 책은 그대로 남아요.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('취소'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                );
                if (yes == true) {
                  await c.deleteList(p.id);
                  if (context.mounted && c.error == null) {
                    Navigator.pop(context);
                  }
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('책 추가 · 제외 · 순서')),
              PopupMenuItem(value: 'rename', child: Text('이름 변경')),
              PopupMenuItem(value: 'delete', child: Text('플레이리스트 삭제')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (c.error != null) Text(c.error!),
          Text(
            '${books.length}권의 이야기',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: books.isEmpty
                    ? null
                    : () => playBooks(context, books),
                icon: const Icon(Icons.play_arrow),
                label: const Text('전체 재생'),
              ),
              TextButton(
                onPressed: books.isEmpty
                    ? null
                    : () => context.read<PlaybackQueue>().append(books),
                child: const Text('최근재생목록에 추가'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SearchAndBadges(catalog: c),
          if (books.isEmpty) const Text('위 메뉴에서 책을 추가해 주세요.'),
          if (books.isNotEmpty) BookTree(books: c.filter(books)),
        ],
      ),
      bottomNavigationBar: const FloatingPlayer(),
    );
  }
}

class PlaylistEditor extends StatefulWidget {
  const PlaylistEditor({super.key, required this.playlist});
  final Playlist playlist;
  @override
  State<PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<PlaylistEditor> {
  late List<String> ids = [...widget.playlist.contentIds];
  String query = '';
  @override
  Widget build(BuildContext context) {
    final c = context.watch<CatalogViewModel>();
    final map = {for (final b in c.books) b.id: b};
    final selected = ids.where(map.containsKey).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('플레이리스트 편집'),
        actions: [
          TextButton(
            onPressed: c.isBusy
                ? null
                : () async {
                    await c.saveList(
                      widget.playlist.copyWith(contentIds: selected),
                    );
                    if (context.mounted && c.error == null) {
                      Navigator.pop(context);
                    }
                  },
            child: const Text('저장'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (c.error != null) Text(c.error!),
          const Text('담은 책 · 손잡이를 끌어 재생 순서를 바꿔요'),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: selected.length,
            onReorderItem: (a, b) => setState(() {
              ids = [...selected];
              ids.insert(b, ids.removeAt(a));
            }),
            itemBuilder: (context, i) {
              final book = map[selected[i]]!;
              return ListTile(
                key: ValueKey(book.id),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
                title: Text(book.title),
                trailing: IconButton(
                  tooltip: '${book.title} 제외',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => ids.remove(book.id)),
                ),
              );
            },
          ),
          const Divider(),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '추가할 책 검색',
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          for (final b in c.books.where(
            (b) =>
                !ids.contains(b.id) &&
                '${b.title} ${c.publisherOf(b)} ${c.seriesTitle(b)}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
          ))
            ListTile(
              title: Text(b.title),
              subtitle: Text('${c.publisherOf(b)} · ${c.seriesTitle(b)}'),
              trailing: IconButton(
                tooltip: '${b.title} 추가',
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => ids.add(b.id)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: const Text('백업 파일'),
        subtitle: const Text('책과 목소리 보관 · 백업 파일 검사'),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const BackupScreen()),
        ),
      ),
      const ListTile(
        leading: Icon(Icons.palette_outlined),
        title: Text('화면 테마'),
        subtitle: Text('휴대전화의 밝은 화면 · 어두운 화면 설정을 따라요.'),
      ),
      ListTile(
        leading: Icon(Icons.pause_circle_outline),
        title: Text('화면을 꺼도 이어 듣기'),
        subtitle: Text(
          context.watch<PlaybackQueue>().backgroundEnabled
              ? '알림·잠금화면에서 재생을 조작해요. 통화나 이어폰 분리 시 멈추며, 편집 중에는 재생을 쉬어요.'
              : '백그라운드 재생을 준비하지 못했어요. 앱을 켜 둔 상태로 들어 주세요.',
        ),
      ),
      ListTile(
        leading: Icon(Icons.phone_android),
        title: Text('내 기기에 저장'),
        subtitle: Text(
          '책과 녹음은 이 기기에 저장해요. 앱을 삭제하면 함께 삭제되며, 설정의 백업 파일 메뉴에서 따로 보관할 수 있어요.',
        ),
      ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title, detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(detail, textAlign: TextAlign.center),
      ],
    ),
  );
}
