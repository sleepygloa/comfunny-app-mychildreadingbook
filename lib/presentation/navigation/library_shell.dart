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
import '../library/book_tag_sheet.dart';
import '../library/catalog_view_model.dart';
import '../library/collections_tab.dart';
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
        title: _tab == 0
            ? _RoomTitle(catalog: catalog)
            : Text(['', '플레이리스트', '모아보기', '설정'][_tab]),
        actions: [
          // 책 등록은 도서관에서만 — 음원 · 영상 넣기는 다음 차례다.
          if (_tab == 1 || (_tab == 0 && catalog.room == LibraryRoom.library))
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
          if (_tab == 0 && catalog.room == LibraryRoom.library)
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
                  // 최근재생목록은 설정 안으로 옮겼다(2026-11-21 오너 결정) — 자리는 모아보기.
                  const CollectionsTab(),
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
                  icon: Icons.collections_bookmark_outlined,
                  selected: false,
                ),
                selectedIcon: StoryTabIcon(
                  icon: Icons.collections_bookmark,
                  selected: true,
                ),
                label: '모아보기',
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

  Widget _books(CatalogViewModel c) =>
      c.room == LibraryRoom.library ? _library(c) : _OtherRoom(catalog: c);

  Widget _library(CatalogViewModel c) => RefreshIndicator(
    onRefresh: c.load,
    child: ListView(
      padding: const EdgeInsets.all(20),
      // 인사 카드를 지우고 검색을 제목 바로 아래에 둔다(2026-11-21 오너 결정).
      children: [
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

  /// ⚙ 를 눌러 연 상태. 평소에는 거르기 줄을 숨긴다 — 책 목록이 먼저 보여야 한다.
  bool _open = false;
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

  Widget _row(List<Widget> chips) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (final chip in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: chip),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final showFilters =
        _open || catalog.query.isNotEmpty || catalog.hasActiveFilters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: '책 제목 · 전집 · 주제 검색',
            suffixIcon: IconButton(
              tooltip: showFilters ? '거르기 닫기' : '거르기',
              isSelected: showFilters,
              icon: const Icon(Icons.tune),
              onPressed: () => setState(() {
                if (showFilters) {
                  // 닫을 때 조건도 함께 푼다 — 숨겨진 조건이 책을 가리면 아이가 "책이 없어졌다"고 느낀다.
                  _open = false;
                  _controller.clear();
                  catalog.search('');
                  catalog.clearFilters();
                } else {
                  _open = true;
                }
              }),
            ),
          ),
          onChanged: catalog.search,
        ),
        const SizedBox(height: 12),
        if (showFilters) ...[
          _row([
            ChoiceChip(
              label: const Text('전체'),
              selected: !catalog.hasActiveFilters,
              onSelected: (_) => catalog.clearFilters(),
            ),
            FilterChip(
              label: const Text('⭐ 즐겨찾기'),
              selected: catalog.favoritesOnly,
              onSelected: catalog.setFavoritesOnly,
            ),
            for (final t in catalog.rootTopics)
              FilterChip(
                label: Text('${t.emoji} ${t.name}'),
                selected: catalog.topicFilter == t.id,
                onSelected: (_) => catalog.selectTopic(
                  catalog.topicFilter == t.id ? null : t.id,
                ),
              ),
          ]),
          _row([
            for (var age = 3; age <= 8; age++)
              FilterChip(
                label: Text('$age세'),
                selected: catalog.ageFilter == age,
                onSelected: (_) =>
                    catalog.selectAge(catalog.ageFilter == age ? null : age),
              ),
            for (final publisher in catalog.publishers)
              FilterChip(
                label: Text(publisher),
                selected: catalog.publisher == publisher,
                onSelected: (_) => catalog.selectPublisher(
                  catalog.publisher == publisher ? null : publisher,
                ),
              ),
          ]),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
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
  Widget build(BuildContext context) {
    final c = context.watch<CatalogViewModel>();
    final tags = c.tagsOf(book);
    final badges = [
      for (final t in c.topicsOf(book))
        _Badge(
          label: '${t.emoji.isEmpty ? '' : '${t.emoji} '}${t.name}',
          color: _topicColor(context, c.rootOf(t.id)?.id ?? t.id),
        ),
      if (tags.ageLabel != null)
        _Badge(
          label: '🎂 ${tags.ageLabel}',
          color: Theme.of(context).colorScheme.tertiaryContainer,
        ),
      _Badge(
        label: '${book.pageCount}쪽',
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    ];
    return ListTile(
      // 줄 높이를 표지 높이(72)에 맞춰 고정한다 — 배지 수가 달라도 줄이 들쭉날쭉하지 않게.
      minTileHeight: 88,
      leading: _CoverWithStar(
        book: book,
        favorite: tags.favorite,
        onStar: () => c.toggleFavorite(book),
      ),
      title: Text(
        '${book.volume == null ? '' : '${book.volume}. '}${book.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // 배지가 많으면 한 줄만 보이고 나머지는 잘린다 — 줄 높이를 고정하려는 것이다.
      // (가로 스크롤 목록은 펼침 상태 저장소(PageStorage)와 부딪혀 쓰지 않는다.)
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          height: 22,
          child: ClipRect(child: Wrap(runSpacing: 8, children: badges)),
        ),
      ),
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
          PopupMenuItem(value: 'tags', child: Text('주제 · 나이 정하기')),
          PopupMenuItem(value: 'edit', child: Text('책 수정')),
          PopupMenuItem(value: 'voice', child: Text('목소리 넣기')),
          PopupMenuItem(value: 'delete', child: Text('책 삭제')),
        ],
      ),
    );
  }

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
    if (action == 'tags') {
      await showBookTagSheet(context, book);
      return;
    }
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
          // 꼬리표도 메타데이터다 — 파일(책 본체)보다 먼저 지운다.
          await c.deleteTagsOf(book.id);
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

  /// 표지 크기를 고정한다 — 사진 비율이 제각각이어도 책 줄이 가지런하게.
  static const double width = 56;
  static const double height = 72;
  @override
  Widget build(BuildContext context) {
    final path = book.coverPath ?? book.pages.firstOrNull?.imagePath;
    final fallback = Container(
      width: BookCover.width,
      height: BookCover.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const BookFriend(size: 48),
    );
    return path == null
        ? fallback
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(sl<MediaStorage>().absolutePathOf(book.id, path)),
              width: BookCover.width,
              height: BookCover.height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
          );
  }
}

/// 표지 오른쪽 아래에 작은 별을 겹친다(2026-11-21 오너 결정). 별만 눌러도 즐겨찾기가 바뀐다.
class _CoverWithStar extends StatelessWidget {
  const _CoverWithStar({
    required this.book,
    required this.favorite,
    required this.onStar,
  });
  final Content book;
  final bool favorite;
  final VoidCallback onStar;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: BookCover.width + 6,
    height: BookCover.height + 6,
    child: Stack(
      children: [
        BookCover(book: book),
        Positioned(
          right: 0,
          bottom: 0,
          child: Semantics(
            button: true,
            label: favorite ? '${book.title} 즐겨찾기 빼기' : '${book.title} 즐겨찾기',
            child: Tooltip(
              message: favorite ? '즐겨찾기 빼기' : '즐겨찾기',
              child: InkResponse(
                onTap: onStar,
                radius: 18,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(blurRadius: 2, color: Color(0x33000000)),
                    ],
                  ),
                  child: Icon(
                    favorite ? Icons.star : Icons.star_border,
                    size: 16,
                    color: const Color(0xFFF2B33D),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

/// 큰 주제마다 같은 색을 준다 — 글자를 못 읽는 아이도 색으로 "과학 책"을 알아본다.
Color _topicColor(BuildContext context, String rootId) {
  const palette = [
    Color(0xFFDCEBFA),
    Color(0xFFDFF3E4),
    Color(0xFFFFE9D6),
    Color(0xFFF3E2F7),
    Color(0xFFFFF4C9),
    Color(0xFFE2F1F3),
  ];
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = palette[rootId.hashCode.abs() % palette.length];
  return dark ? Color.lerp(base, Colors.black, .6)! : base;
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
        leading: const Icon(Icons.history),
        title: const Text('최근재생목록'),
        subtitle: const Text('마지막으로 담은 재생 순서 · 순서 바꾸기 · 비우기'),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const RecentPlaybackScreen()),
        ),
      ),
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

/// 앱바 제목 "작은 도서관 ▾". 누르면 방 고르기 시트가 열린다.
class _RoomTitle extends StatelessWidget {
  const _RoomTitle({required this.catalog});
  final CatalogViewModel catalog;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '방 고르기',
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: catalog.isBusy ? null : () => _pickRoom(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(catalog.room.label, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    ),
  );

  Future<void> _pickRoom(BuildContext context) async {
    final picked = await showModalBottomSheet<LibraryRoom>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Row(
            children: [
              for (final r in LibraryRoom.values)
                Expanded(
                  child: _RoomTile(
                    room: r,
                    selected: r == catalog.room,
                    onTap: () => Navigator.pop(ctx, r),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await catalog.selectRoom(picked);
  }
}

/// 방 하나 — 큰 그림 아래에 이름(2026-11-21 오너 결정: 아이가 보니 글자보다 그림).
class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.selected,
    required this.onTap,
  });
  final LibraryRoom room;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: room.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? scheme.primary : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        room.emoji,
                        style: const TextStyle(fontSize: 48),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                room.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 음악방 · 영상관 책장. 넣기 · 재생은 다음 차례라 지금은 목록만 보인다.
class _OtherRoom extends StatelessWidget {
  const _OtherRoom({required this.catalog});
  final CatalogViewModel catalog;
  @override
  Widget build(BuildContext context) {
    final music = catalog.room == LibraryRoom.music;
    final items = catalog.shelfItems;
    return RefreshIndicator(
      onRefresh: catalog.load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (items.isEmpty)
            _Empty(
              icon: music ? Icons.music_note_outlined : Icons.movie_outlined,
              title: music ? '아직 음원이 없어요' : '아직 영상이 없어요',
              detail: music
                  ? '동요 · 이야기 음원 넣기는 곧 만들어요.\n지금은 작은 도서관에서 책을 들어 주세요.'
                  : '영상 넣기는 곧 만들어요.\n지금은 작은 도서관에서 책을 들어 주세요.',
            ),
          for (final item in items)
            Card(
              child: ListTile(
                leading: Text(
                  catalog.room.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
                title: Text(item.title),
                subtitle: Text(catalog.seriesTitle(item)),
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => catalog.selectRoom(LibraryRoom.library),
              icon: const Text('📚'),
              label: const Text('작은 도서관으로'),
            ),
          ),
        ],
      ),
    );
  }
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

/// 설정 › 최근재생목록. 탭에 있던 목록을 그대로 옮겼다 — 같은 [QueuePanel] 을 쓴다.
class RecentPlaybackScreen extends StatelessWidget {
  const RecentPlaybackScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('최근재생목록')),
    body: const SafeArea(child: QueuePanel()),
    bottomNavigationBar: const FloatingPlayer(),
  );
}
