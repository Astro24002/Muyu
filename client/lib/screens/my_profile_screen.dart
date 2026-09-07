import 'package:flutter/material.dart';

import '../auth/mobile_session_store.dart';
import '../devices/device_management_repository.dart';
import '../models/task_overview.dart';
import '../models/user.dart';
import '../profile/profile_repository.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';
import '../workspace/device_repository.dart';
import '../workspace/workspace_bootstrap_repository.dart';
import 'device_management_screen.dart';
import 'classification_management_screen.dart';
import 'profile_edit_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({
    super.key,
    required this.session,
    required this.repository,
    this.managementRepository,
    this.profileRepository,
    this.sessionStore,
    this.workspaceRepository,
    this.sync,
    this.canWrite = true,
    this.showAppBar = true,
    this.onApprovalCenter,
    this.onWebQrLogin,
  });

  final MobileSession session;
  final DeviceRepository repository;
  final DeviceManagementRepository? managementRepository;
  final ProfileRepository? profileRepository;
  final MobileSessionStore? sessionStore;
  final WorkspaceBootstrapRepository? workspaceRepository;
  final WorkspaceSyncController? sync;
  final bool canWrite;
  final bool showAppBar;
  final VoidCallback? onApprovalCenter;
  final VoidCallback? onWebQrLogin;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late Future<_ProfileData> _profile;
  User? _updatedUser;

  User get _currentUser => _updatedUser ?? widget.session.user;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  void _reload() {
    setState(() => _profile = _loadProfile());
  }

  Future<void> _refresh() async {
    final next = _loadProfile();
    final syncRefresh = widget.sync?.refresh();
    setState(() => _profile = next);
    try {
      await next;
      if (syncRefresh != null) await syncRefresh;
    } catch (_) {
      // FutureBuilder retains the error and lets the user retry.
    }
  }

  Future<_ProfileData> _loadProfile() async {
    final devices =
        await (widget.managementRepository?.list() ??
            widget.repository.listDevices());
    final androidDevices = devices
        .where((device) => device.platform.toUpperCase() == 'ANDROID')
        .toList(growable: false);
    final workspace = widget.workspaceRepository == null
        ? null
        : await widget.workspaceRepository!.loadBootstrap();
    return _ProfileData(devices: androidDevices, workspace: workspace);
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.sync == null
        ? _profileBody(context)
        : AnimatedBuilder(
            animation: widget.sync!,
            builder: (context, _) => _profileBody(context),
          );
    if (!widget.showAppBar) return content;
    return Scaffold(
      appBar: AppBar(
        key: const Key('profile-account-app-bar'),
        title: Text('我的', style: Theme.of(context).textTheme.titleLarge),
        actions: [
          if (widget.onApprovalCenter != null)
            IconButton(
              key: const Key('profile-approval-center'),
              tooltip: '审批中心',
              onPressed: widget.onApprovalCenter,
              icon: const Icon(Icons.rule_outlined),
            ),
          if (widget.onWebQrLogin != null)
            IconButton(
              key: const Key('profile-web-qr-login'),
              tooltip: '扫码登录 Web',
              onPressed: widget.onWebQrLogin,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          IconButton(
            tooltip: '刷新资料',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _profileBody(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      key: const Key('profile-account-content'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(MuyuSpacing.lg),
      children: [
        FutureBuilder<_ProfileData>(
          future: _profile,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(MuyuSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Text('个人信息加载失败，请重试'),
                  const SizedBox(height: MuyuSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              );
            }
            return _profileSections(context, snapshot.data!);
          },
        ),
      ],
    ),
  );

  Widget _profileSections(BuildContext context, _ProfileData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _personalProfile(context, data),
      const SizedBox(height: MuyuSpacing.md),
      _workspaceMatch(data),
      const SizedBox(height: MuyuSpacing.md),
      _classificationManagementTile(),
      const SizedBox(height: MuyuSpacing.md),
      _overviewCard(),
      const SizedBox(height: MuyuSpacing.md),
      _deviceManagementTile(data),
    ],
  );

  Widget _personalProfile(BuildContext context, _ProfileData data) {
    final displayName = _displayName(_currentUser.nickname);
    final currentMember = _memberForUser(_membersFor(data), _currentUser.id);
    final phone = currentMember?.phoneMasked.trim().isNotEmpty == true
        ? currentMember!.phoneMasked
        : _maskPhone(_currentUser.phone);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MuyuSpacing.lg,
          MuyuSpacing.md,
          MuyuSpacing.sm,
          MuyuSpacing.md,
        ),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.account_circle_outlined)),
            const SizedBox(width: MuyuSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    key: const Key('profile-current-display-name'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: MuyuSpacing.xs),
                  Text(phone, key: const Key('profile-current-phone')),
                ],
              ),
            ),
            IconButton(
              key: const Key('profile-edit-name'),
              tooltip: '编辑名称',
              onPressed: widget.profileRepository == null
                  ? null
                  : _editDisplayName,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceMatch(_ProfileData data) {
    final members = _membersFor(data);
    final currentUserId = _currentUser.id;
    final partner = _partnerFor(members, currentUserId);
    final activeMemberCount = members.where(_isActive).length;
    final matched = partner != null && activeMemberCount >= 2;
    final status = switch (data.workspace?.workspace?.matchStatus) {
      WorkspaceMatchStatus.error => '匹配异常',
      WorkspaceMatchStatus.matched => '已匹配 · 2/2 位成员',
      _ => matched ? '已匹配 · 2/2 位成员' : '等待对方',
    };
    // The full name is already shown in the personal-profile section. Keep
    // the avatar pair compact and identify the local slot plainly.
    final currentName = '我';

    return Card(
      key: const Key('profile-workspace-match'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MuyuSpacing.lg,
          MuyuSpacing.md,
          MuyuSpacing.lg,
          MuyuSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_outlined),
                const SizedBox(width: MuyuSpacing.sm),
                const Expanded(child: Text('共享空间')),
                Text(status, key: const Key('profile-match-status')),
              ],
            ),
            const SizedBox(height: MuyuSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _memberAvatar(
                    avatar: const CircleAvatar(
                      child: Icon(Icons.account_circle_outlined),
                    ),
                    label: currentName,
                  ),
                ),
                Icon(
                  Icons.link,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: _memberAvatar(
                    avatar: const CircleAvatar(
                      child: Icon(Icons.account_circle_outlined),
                    ),
                    label: partner == null
                        ? '匹配中'
                        : _displayName(partner.displayName, fallback: '对方'),
                    key: const Key('profile-partner-avatar'),
                    onTap: partner == null ? null : () => _openPartner(partner),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MuyuSpacing.sm),
            Text(
              matched ? '两位成员已连接' : '等待对方加入',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberAvatar({
    required Widget avatar,
    required String label,
    Key? key,
    VoidCallback? onTap,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (key == null) avatar else KeyedSubtree(key: key, child: avatar),
        const SizedBox(height: MuyuSpacing.sm),
        Text(label, overflow: TextOverflow.ellipsis),
      ],
    );
    if (onTap == null) return Center(child: content);
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(6)),
      child: Center(child: content),
    );
  }

  Widget _overviewCard() {
    final overview = TaskOverview.fromTasks(
      widget.sync?.state.snapshot?.tasks ?? const [],
      _currentUser.id,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MuyuSpacing.lg,
          MuyuSpacing.md,
          MuyuSpacing.lg,
          MuyuSpacing.lg,
        ),
        child: _overviewSection(overview, title: '我的概览'),
      ),
    );
  }

  Widget _deviceManagementTile(_ProfileData data) {
    final verified = data.devices.where((device) => device.canWrite).length;
    return Card(
      child: ListTile(
        key: const Key('profile-device-management'),
        leading: const Icon(Icons.devices_outlined),
        title: const Text('设备管理'),
        subtitle: Text('${data.devices.length} 台 Android 设备 · $verified 台已验证'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.managementRepository == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeviceManagementScreen(
                    repository: widget.managementRepository!,
                    canWrite: widget.canWrite,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _classificationManagementTile() {
    final sync = widget.sync;
    final count = sync?.state.classifications.length ?? 0;
    return Card(
      child: ListTile(
        key: const Key('profile-classification-management'),
        leading: const Icon(Icons.label_outline),
        title: const Text('分类管理'),
        subtitle: Text('$count 个已批准分类'),
        trailing: const Icon(Icons.chevron_right),
        onTap: sync == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClassificationManagementScreen(
                    sync: sync,
                    canWrite: widget.canWrite,
                  ),
                ),
              ),
      ),
    );
  }

  List<WorkspaceMemberSummary> _membersFor(_ProfileData data) {
    final workspaceMembers = data.workspace?.workspace?.members;
    if (workspaceMembers?.isNotEmpty == true) return workspaceMembers!;
    final snapshotMembers = widget.sync?.state.snapshot?.members ?? const [];
    return [
      for (final member in snapshotMembers)
        if (member['user_id'] is String)
          WorkspaceMemberSummary(
            userId: member['user_id'] as String,
            displayName: member['display_name'] as String?,
            phoneMasked: member['phone_masked'] as String? ?? '',
            memberSlot: (member['member_slot'] as num?)?.toInt() ?? 0,
            membershipStatus:
                member['membership_status'] as String? ?? 'ACTIVE',
            isCurrent:
                member['is_current'] as bool? ??
                member['user_id'] == _currentUser.id,
          ),
    ];
  }

  WorkspaceMemberSummary? _memberForUser(
    Iterable<WorkspaceMemberSummary> members,
    String userId,
  ) {
    for (final member in members) {
      if (member.userId == userId) return member;
    }
    return null;
  }

  WorkspaceMemberSummary? _partnerFor(
    Iterable<WorkspaceMemberSummary> members,
    String currentUserId,
  ) {
    for (final member in members) {
      if (member.userId != currentUserId && _isActive(member)) return member;
    }
    return null;
  }

  bool _isActive(WorkspaceMemberSummary member) =>
      member.membershipStatus.toUpperCase() == 'ACTIVE';

  Widget _overviewSection(
    TaskOverview overview, {
    required String title,
    String keyPrefix = 'profile-overview',
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: MuyuSpacing.md),
      Wrap(
        spacing: MuyuSpacing.xl,
        runSpacing: MuyuSpacing.md,
        children: [
          _overviewMetric(
            key: Key('$keyPrefix-task-count'),
            label: '任务',
            value: '${overview.taskCount}',
          ),
          _overviewMetric(
            key: Key('$keyPrefix-unfinished-count'),
            label: '未完成',
            value: '${overview.unfinishedCount}',
          ),
          _overviewMetric(
            key: Key('$keyPrefix-completed-count'),
            label: '已完成',
            value: '${overview.completedCount}',
          ),
          _overviewMetric(
            key: Key('$keyPrefix-delay-count'),
            label: '延期次数',
            value: '${overview.delayCount}',
          ),
          _overviewMetric(
            key: Key('$keyPrefix-delay-minutes'),
            label: '延期时长',
            value: overview.formattedTotalDelay,
          ),
        ],
      ),
    ],
  );

  Widget _overviewMetric({
    required Key key,
    required String label,
    required String value,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, key: key, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: MuyuSpacing.xs),
      Text(label),
    ],
  );

  Future<void> _editDisplayName() async {
    final repository = widget.profileRepository;
    if (repository == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          repository: repository,
          sessionStore: widget.sessionStore,
          initialDisplayName: _currentUser.nickname,
          onSaved: (user) => setState(() => _updatedUser = user),
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openPartner(WorkspaceMemberSummary partner) async {
    final overview = TaskOverview.fromTasks(
      widget.sync?.state.snapshot?.tasks ?? const [],
      partner.userId,
    );
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: Padding(
          key: const Key('profile-partner-sheet'),
          padding: const EdgeInsets.fromLTRB(
            MuyuSpacing.xl,
            MuyuSpacing.lg,
            MuyuSpacing.xl,
            MuyuSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    child: Icon(Icons.account_circle_outlined),
                  ),
                  const SizedBox(width: MuyuSpacing.md),
                  Expanded(
                    child: Text(
                      _displayName(partner.displayName, fallback: '对方'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(_isActive(partner) ? '已加入' : '待加入'),
                ],
              ),
              if (partner.phoneMasked.trim().isNotEmpty) ...[
                const SizedBox(height: MuyuSpacing.xs),
                Text(partner.phoneMasked),
              ],
              const Divider(height: 28),
              _overviewSection(
                overview,
                title: '对方概览',
                keyPrefix: 'profile-partner-overview',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayName(String? value, {String fallback = '我的账号'}) =>
      value?.trim().isNotEmpty == true ? value!.trim() : fallback;

  String _maskPhone(String phone) {
    if (phone.length <= 5) return phone;
    final prefixLength = phone.startsWith('+86') ? 3 : 2;
    final maskLength = phone.startsWith('+86')
        ? 6
        : (phone.length - prefixLength - 4).clamp(4, phone.length);
    final mask = List.filled(maskLength, '*').join();
    return '${phone.substring(0, prefixLength)}$mask${phone.substring(phone.length - 4)}';
  }
}

class _ProfileData {
  const _ProfileData({required this.devices, required this.workspace});

  final List<DeviceSummary> devices;
  final WorkspaceBootstrapPayload? workspace;
}
