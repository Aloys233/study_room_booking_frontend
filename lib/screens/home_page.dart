import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import '../models/booking_models.dart';
import '../screens/seat_map_layout.dart';
import '../services/avatar_file_picker.dart';
import '../services/auth_api.dart';
import '../services/booking_api.dart';
import '../widgets/app_notification.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.session,
    required this.onLogout,
    AuthApi? authApi,
    BookingApi? bookingApi,
  }) : _authApi = authApi,
       _bookingApi = bookingApi;

  final LoginSession session;
  final VoidCallback onLogout;
  final AuthApi? _authApi;
  final BookingApi? _bookingApi;

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _HomeSection { booking, records, profile, roomReservation }

class _HomePageState extends State<HomePage> {
  late final AuthApi _authApi;
  late final BookingApi _bookingApi;
  final _roomReservationFormKey = GlobalKey<FormState>();
  final _profileFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailActivationController = TextEditingController();
  final _emailVerificationCodeController = TextEditingController();
  final _profilePasswordController = TextEditingController();
  final _profileConfirmPasswordController = TextEditingController();
  final _purposeController = TextEditingController();
  final _remarkController = TextEditingController();

  List<StudyRoom> _rooms = const [];
  List<TimeSlot> _timeSlots = const [];
  List<SeatMapItem> _seatMap = const [];
  List<ReservationSummary> _reservations = const [];
  List<WaitingQueueEntry> _waitingQueues = const [];
  List<RoomReservation> _roomReservations = const [];

  StudyRoom? _selectedRoom;
  TimeSlot? _selectedSlot;
  SeatMapItem? _selectedSeat;
  StudyRoom? _selectedRoomReservationRoom;
  TimeSlot? _selectedRoomReservationSlot;
  late UserProfile _currentUser;
  DateTime _selectedDate = _today();
  SystemConfig _systemConfig = SystemConfig.fallback;
  SystemConfig _reservationRules = SystemConfig.fallback;
  bool _loading = true;
  bool _loadingSeats = false;
  bool _submitting = false;
  bool _uploadingAvatar = false;
  bool _emailDialogOpen = false;
  bool _loggingOut = false;
  _HomeSection _selectedSection = _HomeSection.booking;
  String? _error;

  bool get _isTeacher => widget.session.user.role == 'TEACHER';

  bool _isValidVerificationCode(String code) {
    final normalized = code.trim().toUpperCase();
    final pattern = RegExp(r'^[A-Z0-9]{6}$');
    return pattern.hasMatch(normalized);
  }

  List<_HomeDestination> get _destinations => [
    const _HomeDestination(
      section: _HomeSection.booking,
      label: '预约',
      icon: Icons.event_seat_rounded,
    ),
    const _HomeDestination(
      section: _HomeSection.records,
      label: '记录',
      icon: Icons.fact_check_rounded,
    ),
    const _HomeDestination(
      section: _HomeSection.profile,
      label: '我的',
      icon: Icons.person_rounded,
    ),
    if (_isTeacher)
      const _HomeDestination(
        section: _HomeSection.roomReservation,
        label: '整室',
        icon: Icons.groups_rounded,
      ),
  ];

  @override
  void initState() {
    super.initState();
    _authApi =
        widget._authApi ?? AuthApi(accessToken: widget.session.accessToken);
    _bookingApi =
        widget._bookingApi ??
        BookingApi(accessToken: widget.session.accessToken);
    _currentUser = widget.session.user;
    _emailController.text = widget.session.user.email ?? '';
    _loadInitialData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailActivationController.dispose();
    _emailVerificationCodeController.dispose();
    _profilePasswordController.dispose();
    _profileConfirmPasswordController.dispose();
    _purposeController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _authApi.getCurrentUser(),
        _bookingApi.fetchRooms(),
        _bookingApi.fetchTimeSlots(reserveDate: _dateText(_today())),
        _bookingApi.fetchReservations(),
        _bookingApi.fetchWaitingQueues(),
        _bookingApi.fetchSystemConfig(),
        _bookingApi.fetchReservationRules(),
        if (_isTeacher) _bookingApi.fetchRoomReservations(),
      ]);
      if (!mounted) return;
      final loadedUser = results[0] as UserProfile;
      final loadedTimeSlots = results[2] as List<TimeSlot>;
      setState(() {
        _currentUser = loadedUser;
        _emailController.text = loadedUser.email ?? '';
        _rooms = results[1] as List<StudyRoom>;
        _timeSlots = loadedTimeSlots;
        _reservations = results[3] as List<ReservationSummary>;
        _waitingQueues = results[4] as List<WaitingQueueEntry>;
        _systemConfig = results[5] as SystemConfig;
        _reservationRules = results[6] as SystemConfig;
        _roomReservations = _isTeacher
            ? results[7] as List<RoomReservation>
            : const [];
        _selectedDate = _today();
        _selectedRoom = _rooms.isEmpty ? null : _rooms.first;
        _selectedSlot = _firstBookableSlotFor(
          _selectedDate,
          room: _selectedRoom,
        );
        _selectedRoomReservationRoom = _rooms.isEmpty ? null : _rooms.first;
        _selectedRoomReservationSlot = _firstBookableSlotFor(
          _selectedDate,
          room: _selectedRoomReservationRoom,
        );
      });
      _scheduleEmailActivationDialog();
      await _loadAvailableSeats();
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '数据加载失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshLists() async {
    final results = await Future.wait([
      _bookingApi.fetchReservations(),
      _bookingApi.fetchWaitingQueues(),
      if (_isTeacher) _bookingApi.fetchRoomReservations(),
    ]);
    if (!mounted) return;
    setState(() {
      _reservations = results[0] as List<ReservationSummary>;
      _waitingQueues = results[1] as List<WaitingQueueEntry>;
      _roomReservations = _isTeacher
          ? results[2] as List<RoomReservation>
          : const [];
    });
  }

  /// 最多可提前预约天数（0 表示仅当天）。
  int get _maxAdvanceDays => _reservationRules.effectiveAdvanceDays;

  /// 轻量刷新：只重拉列表与座位图，保留当前自习室/日期/时段选择。
  Future<void> _manualRefresh() async {
    if (_submitting || _loading) {
      return;
    }
    await _runAction(() async {
      await _refreshTimeSlotsForSelectedDate();
      await _refreshLists();
      await _loadAvailableSeats();
      _showMessage('已刷新');
    });
  }

  Future<void> _refreshTimeSlotsForSelectedDate() async {
    final slots = await _bookingApi.fetchTimeSlots(
      reserveDate: _dateText(_selectedDate),
    );
    if (!mounted) return;
    setState(() {
      _timeSlots = slots;
      _selectedSlot = _firstBookableSlotFor(
        _selectedDate,
        room: _selectedRoom,
        current: _selectedSlot,
      );
      _selectedRoomReservationSlot = _firstBookableSlotFor(
        _selectedDate,
        room: _selectedRoomReservationRoom,
        current: _selectedRoomReservationSlot,
      );
    });
  }

  Future<void> _onDateChanged(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);
    if (normalized == _selectedDate) {
      return;
    }
    final slots = await _bookingApi.fetchTimeSlots(
      reserveDate: _dateText(normalized),
    );
    if (!mounted) return;
    setState(() {
      _selectedDate = normalized;
      _timeSlots = slots;
      _selectedSlot = _firstBookableSlotFor(
        normalized,
        room: _selectedRoom,
        current: _selectedSlot,
      );
      _selectedRoomReservationSlot = _firstBookableSlotFor(
        normalized,
        room: _selectedRoomReservationRoom,
        current: _selectedRoomReservationSlot,
      );
    });
    await _loadAvailableSeats();
  }

  Future<void> _loadAvailableSeats() async {
    final room = _selectedRoom;
    final slot = _selectedSlot;
    if (room == null || slot == null) {
      setState(() {
        _seatMap = const [];
        _selectedSeat = null;
      });
      return;
    }

    setState(() {
      _loadingSeats = true;
      _selectedSeat = null;
    });
    try {
      final seats = await _bookingApi.fetchSeatMap(
        roomId: room.id,
        reserveDate: _dateText(_selectedDate),
        slotId: slot.id,
      );
      if (!mounted) return;
      setState(() {
        _seatMap = seats;
        _selectedSeat = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedSeat == null) {
          return;
        }
        // Keep the initial state unselected even if a child widget
        // unexpectedly emits a selection during the first paint.
        setState(() => _selectedSeat = null);
      });
    } on AuthApiException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
      setState(() => _seatMap = const []);
    } finally {
      if (mounted) {
        setState(() => _loadingSeats = false);
      }
    }
  }

  Future<void> _createReservation() async {
    final room = _selectedRoom;
    final slot = _selectedSlot;
    final seat = _selectedSeat;
    if (room == null || slot == null || seat == null) {
      _showMessage('请选择自习室、时间段和座位');
      return;
    }
    if (!_isSlotBookableForDate(_selectedDate, slot)) {
      setState(
        () => _selectedSlot = _firstBookableSlotFor(_selectedDate, room: room),
      );
      await _loadAvailableSeats();
      _showMessage('该时间段已开始或已结束，请重新选择');
      return;
    }

    await _runAction(() async {
      await _bookingApi.createReservation(
        roomId: room.id,
        seatId: seat.id,
        reserveDate: _dateText(_selectedDate),
        slotId: slot.id,
      );
      _showMessage('预约成功');
      await _loadAvailableSeats();
      await _refreshLists();
    });
  }

  Future<void> _joinWaitingQueue() async {
    final room = _selectedRoom;
    final slot = _selectedSlot;
    if (room == null || slot == null) {
      _showMessage('请选择自习室和时间段');
      return;
    }
    if (!_isSlotBookableForDate(_selectedDate, slot)) {
      setState(
        () => _selectedSlot = _firstBookableSlotFor(_selectedDate, room: room),
      );
      await _loadAvailableSeats();
      _showMessage('该时间段已开始或已结束，请重新选择');
      return;
    }

    await _runAction(() async {
      await _bookingApi.joinWaitingQueue(
        roomId: room.id,
        reserveDate: _dateText(_selectedDate),
        slotId: slot.id,
      );
      _showMessage('已加入候补');
      await _refreshLists();
    });
  }

  Future<void> _createRoomReservation() async {
    if (!_roomReservationFormKey.currentState!.validate()) {
      return;
    }
    final room = _selectedRoomReservationRoom;
    final slot = _selectedRoomReservationSlot;
    if (room == null || slot == null) {
      _showMessage('请选择自习室和时间段');
      return;
    }
    if (!_isSlotBookableForDate(_selectedDate, slot)) {
      setState(
        () => _selectedRoomReservationSlot = _firstBookableSlotFor(
          _selectedDate,
          room: room,
        ),
      );
      _showMessage('该时间段已开始或已结束，请重新选择');
      return;
    }

    await _runAction(() async {
      await _bookingApi.createRoomReservation(
        roomId: room.id,
        purpose: _purposeController.text.trim(),
        reserveDate: _dateText(_selectedDate),
        slotId: slot.id,
        remark: _remarkController.text.trim(),
      );
      _purposeController.clear();
      _remarkController.clear();
      _showMessage('整室预约已提交审核');
      await _refreshLists();
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _submitting = true);
    try {
      await action();
    } on AuthApiException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('操作失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _updateProfile() async {
    if (!_profileFormKey.currentState!.validate()) {
      return;
    }
    final password = _profilePasswordController.text;
    await _runAction(() async {
      await _authApi.updateProfile(
        password: password.isEmpty ? null : password,
      );
      final user = await _authApi.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _currentUser = user;
        _emailController.text = user.email ?? '';
        _profilePasswordController.clear();
        _profileConfirmPasswordController.clear();
      });
      _scheduleEmailActivationDialog();
      _showMessage('个人信息已更新');
    });
  }

  Future<void> _changeAvatar() async {
    if (_submitting || _uploadingAvatar) {
      return;
    }
    setState(() => _uploadingAvatar = true);
    try {
      final file = await pickAvatarFile();
      if (file == null) {
        return;
      }
      final avatarUrl = await _authApi.uploadFile(
        bytes: file.bytes,
        filename: file.filename,
      );
      await _authApi.updateProfile(avatar: avatarUrl);
      final user = await _authApi.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _currentUser = user;
      });
      _showMessage('头像已更新');
    } on AuthApiException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('头像上传失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _bindProfileEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('请输入邮箱');
      return;
    }
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      _showMessage('邮箱格式不正确');
      return;
    }

    await _runAction(() async {
      final currentEmail = _currentUser.email?.trim() ?? '';
      if (email.toLowerCase() == currentEmail.toLowerCase()) {
        await _authApi.resendEmailVerification();
        _showMessage('验证码已发送');
      } else {
        await _authApi.bindEmail(email: email);
        final user = await _authApi.getCurrentUser();
        if (!mounted) return;
        setState(() {
          _currentUser = user;
          _emailController.text = user.email ?? '';
        });
        _showMessage('邮箱已修改，请输入验证码完成验证');
      }
    });
  }

  bool get _requiresEmailActivation =>
      (_currentUser.email == null || _currentUser.email!.trim().isEmpty) ||
      !_currentUser.activated;

  void _scheduleEmailActivationDialog() {
    if (_loggingOut ||
        !_requiresEmailActivation ||
        _emailDialogOpen ||
        !mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_loggingOut ||
          !mounted ||
          !_requiresEmailActivation ||
          _emailDialogOpen) {
        return;
      }
      _showEmailActivationDialog();
    });
  }

  void _logout() {
    _loggingOut = true;
    widget.onLogout();
  }

  void _logoutFromDialog(BuildContext dialogContext) {
    _loggingOut = true;
    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
    widget.onLogout();
  }

  Future<void> _refreshCurrentUserForDialog(
    BuildContext dialogContext,
    void Function(void Function()) setDialogState,
  ) async {
    setDialogState(() => _submitting = true);
    try {
      final user = await _authApi.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _currentUser = user;
        _emailController.text = user.email ?? '';
      });
      if (!_requiresEmailActivation && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
        _showMessage('邮箱已验证');
      }
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('状态刷新失败，请稍后重试');
    } finally {
      if (mounted) {
        setDialogState(() => _submitting = false);
      }
    }
  }

  Future<void> _showEmailActivationDialog() async {
    _emailDialogOpen = true;
    final formKey = GlobalKey<FormState>();
    _emailActivationController.text = _currentUser.email ?? '';
    _emailVerificationCodeController.clear();
    var submitting = false;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final hasEmail =
                  _currentUser.email != null &&
                  _currentUser.email!.trim().isNotEmpty;
              return AlertDialog(
                title: const Text('验证邮箱后继续使用'),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        hasEmail
                            ? '验证码已发送到 ${_currentUser.email}，请输入 6 位数字或大写字母激活账号。'
                            : '请先绑定邮箱，系统会发送验证码。完成验证前无法预约、候补或提交整室申请。',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailActivationController,
                        enabled: !submitting,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: '邮箱',
                          prefixIcon: Icon(Icons.email_rounded),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return '请输入邮箱';
                          if (!email.contains('@') ||
                              email.startsWith('@') ||
                              email.endsWith('@')) {
                            return '邮箱格式不正确';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailVerificationCodeController,
                        enabled: !submitting,
                        keyboardType: TextInputType.visiblePassword,
                        maxLength: 6,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: '验证码',
                          prefixIcon: Icon(Icons.verified_rounded),
                          counterText: '',
                        ),
                        validator: (value) {
                          final code = value?.trim() ?? '';
                          if (code.isEmpty) return '请输入验证码';
                          if (!_isValidVerificationCode(code)) {
                            return '请输入 6 位数字或大写字母';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => _logoutFromDialog(dialogContext),
                    child: const Text('退出登录'),
                  ),
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => _refreshCurrentUserForDialog(
                            dialogContext,
                            setDialogState,
                          ),
                    child: const Text('刷新状态'),
                  ),
                  FilledButton.icon(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setDialogState(() => submitting = true);
                            try {
                              final email = _emailActivationController.text
                                  .trim();
                              if (!hasEmail ||
                                  email.toLowerCase() !=
                                      _currentUser.email!.toLowerCase()) {
                                await _authApi.bindEmail(email: email);
                              } else {
                                await _authApi.resendEmailVerification();
                              }
                              final user = await _authApi.getCurrentUser();
                              if (!mounted) return;
                              setState(() {
                                _currentUser = user;
                                _emailController.text = user.email ?? '';
                              });
                              _showMessage('验证码已发送');
                            } on AuthApiException catch (error) {
                              if (mounted) _showMessage(error.message);
                            } catch (_) {
                              if (mounted) _showMessage('验证码发送失败');
                            } finally {
                              if (mounted) {
                                setDialogState(() => submitting = false);
                              }
                            }
                          },
                    icon: submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mark_email_read_rounded),
                    label: Text(hasEmail ? '重发验证码' : '发送验证码'),
                  ),
                  FilledButton.icon(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setDialogState(() => submitting = true);
                            try {
                              await _authApi.verifyMyEmail(
                                email: _emailActivationController.text.trim(),
                                code: _emailVerificationCodeController.text
                                    .trim()
                                    .toUpperCase(),
                              );
                              final user = await _authApi.getCurrentUser();
                              if (!mounted || !dialogContext.mounted) return;
                              setState(() {
                                _currentUser = user;
                                _emailController.text = user.email ?? '';
                              });
                              Navigator.of(dialogContext).pop();
                              _showMessage('邮箱已验证');
                            } on AuthApiException catch (error) {
                              if (mounted) _showMessage(error.message);
                            } catch (_) {
                              if (mounted) _showMessage('邮箱验证失败');
                            } finally {
                              if (mounted) {
                                setDialogState(() => submitting = false);
                              }
                            }
                          },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('确认验证'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      _emailDialogOpen = false;
      if (mounted && !_loggingOut) _scheduleEmailActivationDialog();
    }
  }

  void _showMessage(String message) {
    AppNotification.show(context, message: message);
  }

  TimeSlot? _firstBookableSlotFor(
    DateTime date, {
    StudyRoom? room,
    TimeSlot? current,
  }) {
    final slots = _bookableSlotsFor(date, room: room);
    if (current != null && slots.any((slot) => slot.id == current.id)) {
      return current;
    }
    return slots.isEmpty ? null : slots.first;
  }

  List<TimeSlot> _bookableSlotsFor(DateTime date, {StudyRoom? room}) {
    return _timeSlots
        .where((slot) => _isSlotBookableForDate(date, slot))
        .where((slot) => _isSlotOpenForRoomDate(room, date, slot))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 430;
    final useBottomNavigation = width < 760;
    final destinations = _destinations;
    final selectedIndex = destinations.indexWhere(
      (destination) => destination.section == _selectedSection,
    );
    final effectiveIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final effectiveSection = destinations[effectiveIndex].section;
    final visibleTimeSlots = _bookableSlotsFor(
      _selectedDate,
      room: _selectedRoom,
    );
    final visibleSelectedSlot =
        _selectedSlot != null &&
            visibleTimeSlots.any((slot) => slot.id == _selectedSlot!.id)
        ? _selectedSlot
        : null;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EB),
      bottomNavigationBar: _loading || _error != null || !useBottomNavigation
          ? null
          : NavigationBar(
              selectedIndex: effectiveIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedSection = destinations[index].section);
              },
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    label: destination.label,
                  ),
              ],
            ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!useBottomNavigation)
              _AppSidebar(
                compact: false,
                user: _currentUser,
                destinations: destinations,
                selectedIndex: effectiveIndex,
                onDestinationSelected: (index) {
                  setState(
                    () => _selectedSection = destinations[index].section,
                  );
                },
                onLogout: _logout,
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ErrorState(message: _error!, onRetry: _loadInitialData)
                  : RefreshIndicator(
                      onRefresh: _loadInitialData,
                      child: _HomeSectionView(
                        compact: compact,
                        section: effectiveSection,
                        children: _sectionChildren(
                          effectiveSection,
                          compact,
                          visibleTimeSlots,
                          visibleSelectedSlot,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sectionChildren(
    _HomeSection section,
    bool compact,
    List<TimeSlot> visibleTimeSlots,
    TimeSlot? visibleSelectedSlot,
  ) {
    return switch (section) {
      _HomeSection.booking => [
        _SectionTitle(
          title: '预约座位',
          subtitle: '选择自习室、日期与时段，挑选心仪座位。',
          icon: Icons.event_seat_rounded,
          onRefresh: _submitting ? null : _manualRefresh,
        ),
        SizedBox(height: compact ? 12 : 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final selector = _RoomSelector(
              rooms: _rooms,
              selectedRoom: _selectedRoom,
              submitting: _submitting,
              onRoomChanged: (room) async {
                setState(() {
                  _selectedRoom = room;
                  _selectedSlot = _firstBookableSlotFor(
                    _selectedDate,
                    room: room,
                    current: _selectedSlot,
                  );
                });
                await _loadAvailableSeats();
              },
            );
            final composer = _ReservationComposer(
              timeSlots: visibleTimeSlots,
              seatMap: _seatMap,
              selectedRoom: _selectedRoom,
              selectedSlot: visibleSelectedSlot,
              selectedSeat: _selectedSeat,
              selectedDate: _selectedDate,
              maxAdvanceDays: _maxAdvanceDays,
              allowWaiting: _systemConfig.allowWaiting,
              loadingSeats: _loadingSeats,
              submitting: _submitting,
              onDateChanged: _onDateChanged,
              onSlotChanged: (slot) async {
                setState(() => _selectedSlot = slot);
                await _loadAvailableSeats();
              },
              onSeatChanged: (seat) => setState(() => _selectedSeat = seat),
              onSubmit: _createReservation,
              onJoinWaiting: _joinWaitingQueue,
            );
            if (!wide) {
              return Column(
                children: [
                  selector,
                  SizedBox(height: compact ? 12 : 18),
                  composer,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: selector),
                const SizedBox(width: 18),
                Expanded(flex: 5, child: composer),
              ],
            );
          },
        ),
      ],
      _HomeSection.records => [
        _SectionTitle(
          title: '我的预约记录',
          subtitle: '座位预约和候补状态集中查看。',
          icon: Icons.fact_check_rounded,
          onRefresh: _submitting ? null : _manualRefresh,
        ),
        SizedBox(height: compact ? 12 : 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final reservations = _ReservationsPanel(
              reservations: _reservations,
              submitting: _submitting,
              onCancel: (id) => _runAction(() async {
                await _bookingApi.cancelReservation(id);
                _showMessage('预约已取消');
                await _loadAvailableSeats();
                await _refreshLists();
              }),
              onCheckIn: (id) => _runAction(() async {
                await _bookingApi.checkInReservation(id);
                _showMessage('签到成功');
                await _refreshLists();
              }),
            );
            final waiting = _WaitingPanel(
              waitingQueues: _waitingQueues,
              submitting: _submitting,
              onCancel: (id) => _runAction(() async {
                await _bookingApi.cancelWaiting(id);
                _showMessage('候补已取消');
                await _refreshLists();
              }),
              onAccept: (id) => _runAction(() async {
                await _bookingApi.acceptWaiting(id);
                _showMessage('候补机会已接受');
                await _loadAvailableSeats();
                await _refreshLists();
              }),
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  reservations,
                  SizedBox(height: compact ? 12 : 18),
                  waiting,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: reservations),
                const SizedBox(width: 18),
                Expanded(child: waiting),
              ],
            );
          },
        ),
      ],
      _HomeSection.profile => [
        _ProfilePanel(
          formKey: _profileFormKey,
          user: _currentUser,
          emailController: _emailController,
          passwordController: _profilePasswordController,
          confirmPasswordController: _profileConfirmPasswordController,
          submitting: _submitting,
          uploadingAvatar: _uploadingAvatar,
          onAvatarTap: _changeAvatar,
          onSubmit: _updateProfile,
          onBindEmail: _bindProfileEmail,
          onLogout: _logout,
        ),
      ],
      _HomeSection.roomReservation => [
        _SectionTitle(
          title: '教师整室预约',
          subtitle: '提交整室申请并查看审核状态。',
          icon: Icons.groups_rounded,
          onRefresh: _submitting ? null : _manualRefresh,
        ),
        SizedBox(height: compact ? 12 : 18),
        _RoomReservationPanel(
          formKey: _roomReservationFormKey,
          purposeController: _purposeController,
          remarkController: _remarkController,
          selectedDate: _selectedDate,
          maxAdvanceDays: _maxAdvanceDays,
          onDateChanged: _onDateChanged,
          rooms: _rooms,
          timeSlots: _bookableSlotsFor(
            _selectedDate,
            room: _selectedRoomReservationRoom,
          ),
          selectedRoom: _selectedRoomReservationRoom,
          selectedSlot:
              _selectedRoomReservationSlot != null &&
                  _bookableSlotsFor(
                    _selectedDate,
                    room: _selectedRoomReservationRoom,
                  ).any((slot) => slot.id == _selectedRoomReservationSlot!.id)
              ? _selectedRoomReservationSlot
              : null,
          roomReservations: _roomReservations,
          submitting: _submitting,
          onRoomChanged: (room) => setState(() {
            _selectedRoomReservationRoom = room;
            _selectedRoomReservationSlot = _firstBookableSlotFor(
              _selectedDate,
              room: room,
              current: _selectedRoomReservationSlot,
            );
          }),
          onSlotChanged: (slot) =>
              setState(() => _selectedRoomReservationSlot = slot),
          onSubmit: _createRoomReservation,
          onCancel: (id) => _runAction(() async {
            await _bookingApi.cancelRoomReservation(id);
            _showMessage('整室预约已取消');
            await _refreshLists();
          }),
        ),
      ],
    };
  }
}

class _HomeDestination {
  const _HomeDestination({
    required this.section,
    required this.label,
    required this.icon,
  });

  final _HomeSection section;
  final String label;
  final IconData icon;
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.compact,
    required this.user,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onLogout,
  });

  final bool compact;
  final UserProfile user;
  final List<_HomeDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 82.0 : 248.0;
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Color(0xFF25332B),
        border: Border(right: BorderSide(color: Color(0x1A000000))),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 18,
          18,
          compact ? 10 : 18,
          18,
        ),
        child: Column(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.stretch,
          children: [
            _SidebarBrand(compact: compact),
            const SizedBox(height: 22),
            _SidebarUser(user: user, compact: compact),
            const SizedBox(height: 22),
            Expanded(
              child: ListView.separated(
                itemCount: destinations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final destination = destinations[index];
                  return _SidebarItem(
                    compact: compact,
                    selected: index == selectedIndex,
                    icon: destination.icon,
                    label: destination.label,
                    onTap: () => onDestinationSelected(index),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            _SidebarItem(
              compact: compact,
              selected: false,
              icon: Icons.logout_rounded,
              label: '退出',
              onTap: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFE0B33D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.event_seat_rounded, color: Color(0xFF25332B)),
    );
    if (compact) {
      return mark;
    }
    return Row(
      children: [
        mark,
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '自习室预约',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFFFFFCF6),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarUser extends StatelessWidget {
  const _SidebarUser({required this.user, required this.compact});

  final UserProfile user;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: compact ? 22 : 24,
      backgroundColor: const Color(0xFF3B4B41),
      foregroundImage: user.avatar != null && user.avatar!.trim().isNotEmpty
          ? NetworkImage(user.avatar!.trim())
          : null,
      child: Text(
        user.realName.isEmpty ? '?' : user.realName[0],
        style: const TextStyle(
          color: Color(0xFFFFFCF6),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    if (compact) {
      return Tooltip(message: user.realName, child: avatar);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF314238),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF465A4E)),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.realName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFFCF6),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${user.loginName} · ${_roleText(user.role)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD6CEC1),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.compact,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool compact;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? const Color(0xFF25332B)
        : const Color(0xFFFFFCF6);
    final child = Material(
      color: selected ? const Color(0xFFE0B33D) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: compact
              ? Icon(
                  icon,
                  color: onTap == null
                      ? foreground.withValues(alpha: 0.45)
                      : foreground,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        color: onTap == null
                            ? foreground.withValues(alpha: 0.45)
                            : foreground,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onTap == null
                                ? foreground.withValues(alpha: 0.45)
                                : foreground,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
    return Tooltip(message: compact ? label : '', child: child);
  }
}

class _HomeSectionView extends StatelessWidget {
  const _HomeSectionView({
    required this.compact,
    required this.section,
    required this.children,
  });

  final bool compact;
  final _HomeSection section;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: PageStorageKey(section),
      padding: EdgeInsets.all(compact ? 12 : 24),
      children: children,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onRefresh,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF27332D),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFFF8F4EA)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF6F675A)),
                ),
              ],
            ),
          ),
          if (onRefresh != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: '刷新',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({
    required this.formKey,
    required this.user,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.submitting,
    required this.uploadingAvatar,
    required this.onAvatarTap,
    required this.onSubmit,
    required this.onBindEmail,
    required this.onLogout,
  });

  final GlobalKey<FormState> formKey;
  final UserProfile user;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool submitting;
  final bool uploadingAvatar;
  final VoidCallback onAvatarTap;
  final VoidCallback onSubmit;
  final VoidCallback onBindEmail;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final summary = _Panel(
          title: '个人中心',
          icon: Icons.person_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _EditableAvatar(
                    user: user,
                    uploading: uploadingAvatar,
                    onTap: onAvatarTap,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.realName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${user.loginName} · ${_roleText(user.role)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF6F675A)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ListLine(
                title: '账号状态',
                subtitle: _userStatusText(user.status),
                trailing: _StatusPill(
                  icon: Icons.verified_rounded,
                  label: _userStatusText(user.status),
                ),
              ),
              _ListLine(
                title: user.role == 'TEACHER' ? '工号' : '学号',
                subtitle: user.userNo ?? user.loginName,
              ),
              _ListLine(
                title: '邮箱',
                subtitle: user.email?.trim().isNotEmpty == true
                    ? user.email!
                    : '未绑定',
                trailing: _StatusPill(
                  icon: user.activated
                      ? Icons.mark_email_read_rounded
                      : Icons.mark_email_unread_rounded,
                  label: user.activated ? '已激活' : '未激活',
                ),
              ),
              const SizedBox(height: 8),
              if (kDebugMode) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    throw StateError('This is test exception');
                  },
                  icon: const Icon(Icons.bug_report_rounded),
                  label: const Text('Verify Sentry Setup'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('退出登录'),
              ),
            ],
          ),
        );

        final form = _Panel(
          title: '资料设置',
          icon: Icons.manage_accounts_rounded,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _EditableAvatar(
                    user: user,
                    radius: 44,
                    uploading: uploadingAvatar,
                    onTap: onAvatarTap,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    prefixIcon: Icon(Icons.email_rounded),
                  ),
                ),
                if (user.activated) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: submitting ? null : onBindEmail,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('修改邮箱'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码',
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return null;
                    }
                    return value.length < 6 ? '密码至少 6 位' : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认新密码',
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                  validator: (value) {
                    if (passwordController.text.isEmpty) {
                      return null;
                    }
                    return value == passwordController.text ? null : '两次密码不一致';
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: submitting ? null : onSubmit,
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('保存修改'),
                ),
              ],
            ),
          ),
        );

        if (!wide) {
          return Column(children: [summary, const SizedBox(height: 18), form]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: summary),
            const SizedBox(width: 18),
            Expanded(flex: 5, child: form),
          ],
        );
      },
    );
  }
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.user,
    required this.uploading,
    required this.onTap,
    this.radius = 34,
  });

  final UserProfile user;
  final bool uploading;
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user.avatar?.trim();
    final initials = user.realName.isEmpty ? '?' : user.realName[0];
    final size = radius * 2;

    return Tooltip(
      message: uploading ? '头像上传中' : '更换头像',
      child: Semantics(
        button: true,
        label: '更换头像',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: uploading ? null : onTap,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: radius,
                  backgroundColor: const Color(0xFF27332D),
                  foregroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: const Color(0xFFF8F4EA),
                      fontWeight: FontWeight.w900,
                      fontSize: radius * 0.64,
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F4EA),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF27332D)),
                    ),
                    child: SizedBox.square(
                      dimension: radius * 0.82,
                      child: uploading
                          ? const Padding(
                              padding: EdgeInsets.all(5),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.photo_camera_rounded,
                              size: radius * 0.42,
                              color: const Color(0xFF27332D),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.selectedDate,
    required this.maxAdvanceDays,
    required this.enabled,
    required this.onChanged,
  });

  final DateTime selectedDate;

  /// 最多可提前的天数，0 表示仅当天。
  final int maxAdvanceDays;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  static const int _maxVisibleChips = 14;

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final visibleDays = maxAdvanceDays < _maxVisibleChips
        ? maxAdvanceDays
        : _maxVisibleChips;
    final dates = [
      for (var i = 0; i <= visibleDays; i++) today.add(Duration(days: i)),
    ];
    final hasMore = maxAdvanceDays > _maxVisibleChips;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_rounded, size: 18, color: Color(0xFFC9A227)),
            const SizedBox(width: 8),
            Text(
              maxAdvanceDays <= 0 ? '预约日期（仅限当天）' : '预约日期',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF51483B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 62,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final date in dates) ...[
                _DateChip(
                  date: date,
                  today: today,
                  selected: _isSameDate(date, selectedDate),
                  onTap: enabled ? () => onChanged(date) : null,
                ),
                const SizedBox(width: 8),
              ],
              if (hasMore)
                _MoreDateButton(
                  enabled: enabled,
                  selectedDate: selectedDate,
                  firstDate: today,
                  lastDate: today.add(Duration(days: maxAdvanceDays)),
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.date,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final DateTime today;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final diff = date.difference(today).inDays;
    final top = switch (diff) {
      0 => '今天',
      1 => '明天',
      _ => _weekdayShort(date.weekday),
    };
    final fg = selected ? const Color(0xFF25332B) : const Color(0xFF51483B);
    return Material(
      color: selected ? const Color(0xFFE0B33D) : const Color(0xFFFBF8F1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 60,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFFC9A227)
                  : const Color(0xFFE8DFCF),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  top,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.month}/${date.day}',
                  style: TextStyle(color: fg, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreDateButton extends StatelessWidget {
  const _MoreDateButton({
    required this.enabled,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
  });

  final bool enabled;
  final DateTime selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pick(BuildContext context) async {
    final initial = selectedDate.isBefore(firstDate)
        ? firstDate
        : (selectedDate.isAfter(lastDate) ? lastDate : selectedDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) {
      onChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: OutlinedButton(
        onPressed: enabled ? () => _pick(context) : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month_rounded, size: 18),
            SizedBox(height: 2),
            Text('更多', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ReservationComposer extends StatelessWidget {
  const _ReservationComposer({
    required this.timeSlots,
    required this.seatMap,
    required this.selectedRoom,
    required this.selectedSlot,
    required this.selectedSeat,
    required this.selectedDate,
    required this.maxAdvanceDays,
    required this.allowWaiting,
    required this.loadingSeats,
    required this.submitting,
    required this.onDateChanged,
    required this.onSlotChanged,
    required this.onSeatChanged,
    required this.onSubmit,
    required this.onJoinWaiting,
  });

  final List<TimeSlot> timeSlots;
  final List<SeatMapItem> seatMap;
  final StudyRoom? selectedRoom;
  final TimeSlot? selectedSlot;
  final SeatMapItem? selectedSeat;
  final DateTime selectedDate;
  final int maxAdvanceDays;
  final bool allowWaiting;
  final bool loadingSeats;
  final bool submitting;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeSlot?> onSlotChanged;
  final ValueChanged<SeatMapItem?> onSeatChanged;
  final VoidCallback onSubmit;
  final VoidCallback onJoinWaiting;

  @override
  Widget build(BuildContext context) {
    final noRoom = selectedRoom == null;
    return _Panel(
      title: '创建座位预约',
      icon: Icons.event_available_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DateStrip(
            selectedDate: selectedDate,
            maxAdvanceDays: maxAdvanceDays,
            enabled: !submitting,
            onChanged: onDateChanged,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<TimeSlot>(
            key: ValueKey(
              'seat-slot-${_dateText(selectedDate)}-${selectedSlot?.id ?? 'none'}-${timeSlots.length}',
            ),
            initialValue: selectedSlot,
            isExpanded: true,
            itemHeight: null,
            items: timeSlots
                .map(
                  (slot) => DropdownMenuItem(
                    value: slot,
                    child: _TimeSlotDropdownLabel(slot: slot),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => timeSlots
                .map((slot) => _TimeSlotSelectedLabel(slot: slot))
                .toList(),
            onChanged: submitting ? null : onSlotChanged,
            decoration: const InputDecoration(
              labelText: '可预约时间段',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              prefixIcon: Icon(Icons.schedule_rounded),
            ),
          ),
          const SizedBox(height: 14),
          if (noRoom)
            const _EmptyInline(
              icon: Icons.meeting_room_rounded,
              text: '请先选择自习室。',
            )
          else if (loadingSeats)
            const LinearProgressIndicator()
          else if (seatMap.isEmpty)
            _EmptyInline(
              icon: Icons.hourglass_empty_rounded,
              text: selectedSlot == null
                  ? '当前日期没有可预约时间段。'
                  : (allowWaiting ? '当前条件下没有座位图数据，可以加入候补队列。' : '当前条件下没有座位图数据。'),
              actionLabel: allowWaiting ? '加入候补' : null,
              onAction: submitting || selectedSlot == null || !allowWaiting
                  ? null
                  : onJoinWaiting,
            )
          else
            _SeatMapGrid(
              seats: seatMap,
              selectedSeat: selectedSeat,
              submitting: submitting,
              allowWaiting: allowWaiting,
              onSeatChanged: onSeatChanged,
              onJoinWaiting: onJoinWaiting,
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed:
                submitting || selectedSlot == null || selectedSeat == null
                ? null
                : onSubmit,
            icon: submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: const Text('提交预约'),
          ),
        ],
      ),
    );
  }
}

class _RoomSelector extends StatelessWidget {
  const _RoomSelector({
    required this.rooms,
    required this.selectedRoom,
    required this.submitting,
    required this.onRoomChanged,
  });

  final List<StudyRoom> rooms;
  final StudyRoom? selectedRoom;
  final bool submitting;
  final ValueChanged<StudyRoom?> onRoomChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '选择自习室',
      icon: Icons.apartment_rounded,
      child: rooms.isEmpty
          ? const _EmptyText('暂无开放自习室')
          : Column(
              children: [
                for (final room in rooms)
                  _RoomOption(
                    room: room,
                    selected: room.id == selectedRoom?.id,
                    onTap: submitting ? null : () => onRoomChanged(room),
                  ),
              ],
            ),
    );
  }
}

class _RoomOption extends StatelessWidget {
  const _RoomOption({
    required this.room,
    required this.selected,
    required this.onTap,
  });

  final StudyRoom room;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEEF3E9) : const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFF2F6B4F) : const Color(0xFFE8DFCF),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.meeting_room_rounded,
                  color: selected
                      ? const Color(0xFF2F6B4F)
                      : const Color(0xFF6F675A),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        room.location.isEmpty ? '位置待补充' : room.location,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF6F675A)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(
                  icon: Icons.event_seat_rounded,
                  label: '${room.totalSeats}',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatMapGrid extends StatelessWidget {
  const _SeatMapGrid({
    required this.seats,
    required this.selectedSeat,
    required this.submitting,
    required this.allowWaiting,
    required this.onSeatChanged,
    required this.onJoinWaiting,
  });

  final List<SeatMapItem> seats;
  final SeatMapItem? selectedSeat;
  final bool submitting;
  final bool allowWaiting;
  final ValueChanged<SeatMapItem?> onSeatChanged;
  final VoidCallback onJoinWaiting;

  bool get _hasAvailableSeat =>
      seats.any((seat) => seat.displayStatus == 'AVAILABLE');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: const [
            _SeatLegend(color: Color(0xFF2F6B4F), label: '可选'),
            _SeatLegend(color: Color(0xFFC9A227), label: '已选'),
            _SeatLegend(color: Color(0xFFB8AFA2), label: '已占'),
            _SeatLegend(color: Color(0xFF8F3D3D), label: '不可用'),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = MediaQuery.sizeOf(context).width < 430;
            final metrics = computeSeatMapBoardMetrics(
              seats: seats,
              maxWidth: constraints.maxWidth,
              compact: compact,
            );

            return _ZoomableSeatMapBoard(
              viewportHeight: metrics.viewportHeight,
              initialScale: metrics.initialScale,
              boardWidth: metrics.boardWidth,
              boardHeight: metrics.boardHeight,
              cellSize: metrics.cellSize,
              gap: 8,
              seats: seats,
              selectedSeat: selectedSeat,
              submitting: submitting,
              onSeatChanged: onSeatChanged,
            );
          },
        ),
        if (!_hasAvailableSeat) ...[
          const SizedBox(height: 12),
          _EmptyInline(
            icon: Icons.hourglass_empty_rounded,
            text: allowWaiting ? '当前时间段已无可选座位，可以加入候补。' : '当前时间段已无可选座位。',
            actionLabel: allowWaiting ? '加入候补' : null,
            onAction: submitting || !allowWaiting ? null : onJoinWaiting,
          ),
        ],
      ],
    );
  }
}

class _ZoomableSeatMapBoard extends StatefulWidget {
  const _ZoomableSeatMapBoard({
    required this.viewportHeight,
    required this.initialScale,
    required this.boardWidth,
    required this.boardHeight,
    required this.cellSize,
    required this.gap,
    required this.seats,
    required this.selectedSeat,
    required this.submitting,
    required this.onSeatChanged,
  });

  final double viewportHeight;
  final double initialScale;
  final double boardWidth;
  final double boardHeight;
  final double cellSize;
  final double gap;
  final List<SeatMapItem> seats;
  final SeatMapItem? selectedSeat;
  final bool submitting;
  final ValueChanged<SeatMapItem?> onSeatChanged;

  @override
  State<_ZoomableSeatMapBoard> createState() => _ZoomableSeatMapBoardState();
}

class _ZoomableSeatMapBoardState extends State<_ZoomableSeatMapBoard> {
  late final TransformationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _resetScale();
  }

  @override
  void didUpdateWidget(_ZoomableSeatMapBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boardWidth != widget.boardWidth ||
        oldWidget.boardHeight != widget.boardHeight ||
        oldWidget.initialScale != widget.initialScale) {
      _resetScale();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetScale() {
    _controller.value = Matrix4.diagonal3Values(
      widget.initialScale,
      widget.initialScale,
      1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFBF8F1),
          border: Border.all(color: const Color(0xFFE8DFCF)),
        ),
        child: SizedBox(
          height: widget.viewportHeight,
          child: InteractiveViewer(
            constrained: false,
            alignment: Alignment.topLeft,
            boundaryMargin: const EdgeInsets.all(96),
            minScale: 0.45,
            maxScale: 3,
            transformationController: _controller,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: widget.boardWidth,
                height: widget.boardHeight,
                child: Stack(
                  children: [
                    for (final item in widget.seats)
                      Positioned(
                        left: item.x * (widget.cellSize + widget.gap),
                        top: item.y * (widget.cellSize + widget.gap),
                        width:
                            item.w * widget.cellSize +
                            (item.w - 1) * widget.gap,
                        height:
                            item.h * widget.cellSize +
                            (item.h - 1) * widget.gap,
                        child: _SeatMapTile(
                          item: item,
                          selected:
                              widget.selectedSeat?.id == item.id && item.isSeat,
                          submitting: widget.submitting,
                          onSeatChanged: widget.onSeatChanged,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatMapTile extends StatelessWidget {
  const _SeatMapTile({
    required this.item,
    required this.selected,
    required this.submitting,
    required this.onSeatChanged,
  });

  final SeatMapItem item;
  final bool selected;
  final bool submitting;
  final ValueChanged<SeatMapItem?> onSeatChanged;

  @override
  Widget build(BuildContext context) {
    if (!item.isSeat) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: _facilityColor(item.type),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x22000000)),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _facilityIcon(item.type),
                    size: 16,
                    color: const Color(0xFF5D5549),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.label ?? _facilityLabel(item.type),
                    style: const TextStyle(
                      color: Color(0xFF5D5549),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final enabled = item.isAvailable && !submitting;
    return Tooltip(
      message: '${item.seatNo} · ${_seatDisplayStatusText(item.displayStatus)}',
      child: Material(
        color: _seatColor(item.displayStatus, selected),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => onSeatChanged(item) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? const Color(0xFF27332D)
                    : const Color(0x22000000),
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_seat_rounded,
                    size: 18,
                    color: _seatTextColor(item.displayStatus, selected),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.seatNo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _seatTextColor(item.displayStatus, selected),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatLegend extends StatelessWidget {
  const _SeatLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6F675A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TimeSlotDropdownLabel extends StatelessWidget {
  const _TimeSlotDropdownLabel({required this.slot});

  final TimeSlot slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.slotName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${slot.startTime}-${slot.endTime}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B6258),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeSlotSelectedLabel extends StatelessWidget {
  const _TimeSlotSelectedLabel({required this.slot});

  final TimeSlot slot;

  @override
  Widget build(BuildContext context) {
    return Text(slot.label, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

class _ReservationsPanel extends StatelessWidget {
  const _ReservationsPanel({
    required this.reservations,
    required this.submitting,
    required this.onCancel,
    required this.onCheckIn,
  });

  final List<ReservationSummary> reservations;
  final bool submitting;
  final ValueChanged<int> onCancel;
  final ValueChanged<int> onCheckIn;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '我的座位预约',
      icon: Icons.fact_check_rounded,
      child: reservations.isEmpty
          ? const _EmptyText('还没有预约记录')
          : Column(
              children: [
                for (final item in reservations)
                  _ListLine(
                    title: '${item.roomName} · ${item.seatNo}',
                    subtitle:
                        '${_reservationScheduleText(item)} · ${_reservationStatusText(item.status)}',
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        if (item.status == 'PENDING_CHECKIN')
                          IconButton(
                            tooltip: '签到',
                            onPressed: submitting
                                ? null
                                : () => onCheckIn(item.id),
                            icon: const Icon(Icons.login_rounded),
                          ),
                        if (item.status == 'PENDING_CHECKIN')
                          IconButton(
                            tooltip: '取消预约',
                            onPressed: submitting
                                ? null
                                : () => onCancel(item.id),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({
    required this.waitingQueues,
    required this.submitting,
    required this.onCancel,
    required this.onAccept,
  });

  final List<WaitingQueueEntry> waitingQueues;
  final bool submitting;
  final ValueChanged<int> onCancel;
  final ValueChanged<int> onAccept;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '我的候补',
      icon: Icons.hourglass_top_rounded,
      child: waitingQueues.isEmpty
          ? const _EmptyText('暂无候补记录')
          : Column(
              children: [
                for (final item in waitingQueues)
                  _ListLine(
                    title: item.roomName ?? '自习室 #${item.roomId}',
                    subtitle:
                        '${_waitingScheduleText(item)} · ${_waitingStatusText(item.status)}',
                    trailing: item.status == 'WAITING'
                        ? Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                tooltip: '接受候补（转为预约）',
                                onPressed: submitting
                                    ? null
                                    : () => onAccept(item.id),
                                icon: const Icon(Icons.done_rounded),
                              ),
                              IconButton(
                                tooltip: '取消候补',
                                onPressed: submitting
                                    ? null
                                    : () => onCancel(item.id),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            ),
    );
  }
}

class _RoomReservationPanel extends StatelessWidget {
  const _RoomReservationPanel({
    required this.formKey,
    required this.purposeController,
    required this.remarkController,
    required this.selectedDate,
    required this.maxAdvanceDays,
    required this.onDateChanged,
    required this.rooms,
    required this.timeSlots,
    required this.selectedRoom,
    required this.selectedSlot,
    required this.roomReservations,
    required this.submitting,
    required this.onRoomChanged,
    required this.onSlotChanged,
    required this.onSubmit,
    required this.onCancel,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController purposeController;
  final TextEditingController remarkController;
  final DateTime selectedDate;
  final int maxAdvanceDays;
  final ValueChanged<DateTime> onDateChanged;
  final List<StudyRoom> rooms;
  final List<TimeSlot> timeSlots;
  final StudyRoom? selectedRoom;
  final TimeSlot? selectedSlot;
  final List<RoomReservation> roomReservations;
  final bool submitting;
  final ValueChanged<StudyRoom?> onRoomChanged;
  final ValueChanged<TimeSlot?> onSlotChanged;
  final VoidCallback onSubmit;
  final ValueChanged<int> onCancel;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '教师整室预约',
      icon: Icons.groups_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Form(
            key: formKey,
            child: Column(
              children: [
                _DateStrip(
                  selectedDate: selectedDate,
                  maxAdvanceDays: maxAdvanceDays,
                  enabled: !submitting,
                  onChanged: onDateChanged,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<StudyRoom>(
                  initialValue: selectedRoom,
                  items: rooms
                      .map(
                        (room) => DropdownMenuItem(
                          value: room,
                          child: Text(room.name),
                        ),
                      )
                      .toList(),
                  onChanged: submitting ? null : onRoomChanged,
                  decoration: const InputDecoration(
                    labelText: '整室预约自习室',
                    prefixIcon: Icon(Icons.meeting_room_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TimeSlot>(
                  key: ValueKey(
                    'room-slot-${_dateText(selectedDate)}-${selectedSlot?.id ?? 'none'}-${timeSlots.length}',
                  ),
                  initialValue: selectedSlot,
                  isExpanded: true,
                  itemHeight: null,
                  items: timeSlots
                      .map(
                        (slot) => DropdownMenuItem(
                          value: slot,
                          child: _TimeSlotDropdownLabel(slot: slot),
                        ),
                      )
                      .toList(),
                  selectedItemBuilder: (context) => timeSlots
                      .map((slot) => _TimeSlotSelectedLabel(slot: slot))
                      .toList(),
                  onChanged: submitting ? null : onSlotChanged,
                  decoration: const InputDecoration(
                    labelText: '整室预约时间段',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: Icon(Icons.schedule_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: purposeController,
                  decoration: const InputDecoration(
                    labelText: '用途',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? '请输入用途' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: remarkController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed:
                submitting || selectedRoom == null || selectedSlot == null
                ? null
                : onSubmit,
            icon: const Icon(Icons.send_rounded),
            label: const Text('提交整室预约'),
          ),
          const SizedBox(height: 18),
          if (roomReservations.isEmpty)
            const _EmptyText('暂无整室预约记录')
          else
            for (final item in roomReservations)
              _ListLine(
                title: item.roomName ?? '自习室 #${item.roomId}',
                subtitle:
                    '${_roomReservationScheduleText(item)} · ${_roomReservationStatusText(item.status)}',
                trailing: item.status == 'PENDING_APPROVAL'
                    ? IconButton(
                        tooltip: '取消整室预约',
                        onPressed: submitting ? null : () => onCancel(item.id),
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
              ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({this.title, this.icon, required this.child});

  final String? title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2DACB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x101B241F),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: const Color(0xFFC9A227)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _ListLine extends StatelessWidget {
  const _ListLine({required this.title, required this.subtitle, this.trailing});

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: compact ? 2 : 1,
          style: const TextStyle(color: Color(0xFF6F675A)),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8DFCF)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                textBlock,
                if (trailing != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: trailing!),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: textBlock),
                if (trailing != null) ...[const SizedBox(width: 10), trailing!],
              ],
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6E0CC)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF27332D)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    final label = actionLabel;
    final hasAction = label != null && label.isNotEmpty;
    final content = Row(
      children: [
        Icon(icon, color: const Color(0xFFC9A227)),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8DFCF)),
      ),
      child: !hasAction
          ? content
          : compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: onAction, child: Text(label)),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: content),
                TextButton(onPressed: onAction, child: Text(label)),
              ],
            ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text, style: const TextStyle(color: Color(0xFF6F675A))),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

String _dateText(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _weekdayShort(int weekday) {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  if (weekday < 1 || weekday > 7) {
    return '';
  }
  return '周${names[weekday - 1]}';
}

bool _isSlotBookableForDate(DateTime date, TimeSlot slot) {
  final today = DateTime.now();
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final normalizedToday = DateTime(today.year, today.month, today.day);
  if (normalizedDate.isBefore(normalizedToday)) {
    return false;
  }
  if (normalizedDate.isAfter(normalizedToday)) {
    return true;
  }

  final endTime = _parseTimeOfDay(slot.endTime);
  if (endTime == null) {
    return false;
  }
  return today.hour < endTime.hour ||
      (today.hour == endTime.hour && today.minute < endTime.minute);
}

bool _isSlotOpenForRoomDate(StudyRoom? room, DateTime date, TimeSlot slot) {
  if (room == null) {
    return true;
  }
  final weekday = date.weekday;
  if (room.openSchedule.isNotEmpty) {
    return room.openSchedule.any(
      (item) => item.weekday == weekday && item.slotIds.contains(slot.id),
    );
  }
  if (room.openWeekdays.isNotEmpty) {
    return room.openWeekdays.contains(weekday);
  }
  return true;
}

TimeOfDay? _parseTimeOfDay(String value) {
  final parts = value.split(':');
  if (parts.length < 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

String _roleText(String role) {
  return switch (role) {
    'STUDENT' => '学生',
    'TEACHER' => '教师',
    'OUTSIDER' => '校外人员',
    _ => role,
  };
}

String _userStatusText(String status) {
  return switch (status) {
    'NORMAL' => '正常',
    'DISABLED' => '已停用',
    _ => status,
  };
}

String _reservationStatusText(String status) {
  return switch (status) {
    'PENDING_CHECKIN' => '待签到',
    'CHECKED_IN' => '已签到',
    'CANCELLED' => '已取消',
    'EXPIRED' => '已过期',
    'FINISHED' => '已完成',
    _ => status,
  };
}

String _reservationScheduleText(ReservationSummary item) {
  final startTime = _extractClockText(item.reserveStartAt);
  final endTime = _extractClockText(item.reserveEndAt);
  if (startTime != null && endTime != null) {
    return '${item.reserveDate} $startTime-$endTime';
  }
  if (startTime != null) {
    return '${item.reserveDate} $startTime';
  }
  final slotName = item.slotName?.trim();
  if (slotName != null && slotName.isNotEmpty) {
    return '${item.reserveDate} $slotName';
  }
  return item.reserveDate;
}

String _waitingScheduleText(WaitingQueueEntry item) {
  final startTime = _extractClockText(item.startTime);
  final endTime = _extractClockText(item.endTime);
  if (startTime != null && endTime != null) {
    return '${item.reserveDate} $startTime-$endTime';
  }
  final slotName = item.slotName?.trim();
  if (slotName != null && slotName.isNotEmpty) {
    return '${item.reserveDate} $slotName';
  }
  return item.reserveDate;
}

String _roomReservationScheduleText(RoomReservation item) {
  final startTime = _extractClockText(item.startTime);
  final endTime = _extractClockText(item.endTime);
  if (startTime != null && endTime != null) {
    return '${item.reserveDate} $startTime-$endTime';
  }
  final slotName = item.slotName?.trim();
  if (slotName != null && slotName.isNotEmpty) {
    return '${item.reserveDate} $slotName';
  }
  return item.reserveDate;
}

String? _extractClockText(String? value) {
  if (value == null) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed != null) {
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final plainMatch = RegExp(r'^(\d{2}:\d{2})').firstMatch(value);
  return plainMatch?.group(1);
}

String _waitingStatusText(String status) {
  return switch (status) {
    'WAITING' => '候补中',
    'ACCEPTED' => '已转预约',
    'CANCELLED' => '已取消',
    _ => status,
  };
}

String _roomReservationStatusText(String status) {
  return switch (status) {
    'PENDING_APPROVAL' => '待审核',
    'APPROVED' => '已通过',
    'REJECTED' => '已驳回',
    'CANCELLED' => '已取消',
    'FINISHED' => '已完成',
    _ => status,
  };
}

String _seatDisplayStatusText(String status) {
  return switch (status) {
    'AVAILABLE' => '可预约',
    'OCCUPIED' => '已占用',
    'BROKEN' => '故障',
    'DISABLED' => '停用',
    _ => status,
  };
}

Color _seatColor(String status, bool selected) {
  if (selected) {
    return const Color(0xFFC9A227);
  }
  return switch (status) {
    'AVAILABLE' => const Color(0xFF2F6B4F),
    'OCCUPIED' => const Color(0xFFE3D9CB),
    'BROKEN' => const Color(0xFF8F3D3D),
    'DISABLED' => const Color(0xFFB8AFA2),
    _ => const Color(0xFFE3D9CB),
  };
}

Color _seatTextColor(String status, bool selected) {
  if (selected || status == 'AVAILABLE' || status == 'BROKEN') {
    return Colors.white;
  }
  return const Color(0xFF51483B);
}

Color _facilityColor(String type) {
  return switch (type) {
    'AISLE' => const Color(0xFFF0E7D8),
    'WINDOW' => const Color(0xFFD9E9EA),
    'DOOR' => const Color(0xFFE8DDC9),
    'PODIUM' => const Color(0xFFD8D2C2),
    'WALL' => const Color(0xFFCFC8BC),
    'COLUMN' => const Color(0xFFD7D0C4),
    _ => const Color(0xFFE3D9CB),
  };
}

IconData _facilityIcon(String type) {
  return switch (type) {
    'AISLE' => Icons.swap_horiz_rounded,
    'WINDOW' => Icons.window_rounded,
    'DOOR' => Icons.door_front_door_rounded,
    'PODIUM' => Icons.co_present_rounded,
    'WALL' => Icons.horizontal_rule_rounded,
    'COLUMN' => Icons.view_column_rounded,
    _ => Icons.grid_view_rounded,
  };
}

String _facilityLabel(String type) {
  return switch (type) {
    'AISLE' => '走廊',
    'WINDOW' => '窗',
    'DOOR' => '门',
    'PODIUM' => '讲台',
    'WALL' => '墙',
    'COLUMN' => '柱',
    _ => type,
  };
}
