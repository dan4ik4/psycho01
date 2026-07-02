import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum SortType { none, priceLow, priceHigh, rating }

const Color kDeepPurple = Color(0xFFB0A6E8);
const Color kAccentPurple = Color(0xFF7862D6);
const Color kWarmWhite = Color(0xFFF6F8FD);
const Color kTextPrimary = Color(0xFF323045);
const Color kTextSecondary = Color(0xFF706D8C);
const Color kWeekendRed = Color(0xFFFF8A80);

class Specialist {
  final String id;
  final String name;
  final String bio;
  final String spec;
  final String price;
  final String image;
  double rating;
  final List<String> categories;

  Specialist({
    required this.id, required this.name, required this.bio,
    required this.spec, required this.price, required this.image,
    required this.rating, required this.categories,
  });
}

class SpecialistListScreen extends StatefulWidget {
  final Function(Map<String, dynamic>)? onBookingConfirmed;

  const SpecialistListScreen({super.key, this.onBookingConfirmed});

  @override
  _SpecialistListScreenState createState() => _SpecialistListScreenState();
}

class _SpecialistListScreenState extends State<SpecialistListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String selectedCategory = "Все";
  SortType activeSort = SortType.none;
  List<Specialist> filteredSpecialists = [];
  List<String> favoriteIds = [];
  SharedPreferences? _prefs;

  // Текущая заявка пользователя
  Map<String, dynamic>? myAssignment;

  final List<String> allCategories = ["Все", "❤️ Избранные", "Тревога", "Депрессия", "Семья", "Выгорание", "Психосоматика", "Карьера"];

  final List<Specialist> specialists = [
    Specialist(id: "1", name: "Елена Маркова", spec: "Гештальт-терапевт", bio: "Специализируюсь на вопросах самооценки и выгорания.", price: "85", image: "https://i.pravatar.cc/150?img=32", rating: 4.9, categories: ["Все", "Выгорание"]),
    Specialist(id: "2", name: "Игорь Петров", spec: "КБТ специалист", bio: "Работа с тревожными расстройствами и фобиями.", price: "90", image: "https://i.pravatar.cc/150?img=11", rating: 4.8, categories: ["Все", "Тревога"]),
    Specialist(id: "3", name: "Марина Сокол", spec: "Семейный психолог", bio: "Помогаю парам наладить коммуникацию.", price: "110", image: "https://i.pravatar.cc/150?img=45", rating: 5.0, categories: ["Все", "Семья"]),
    Specialist(id: "4", name: "Дмитрий Волков", spec: "Психоаналитик", bio: "Глубинная работа с подсознанием.", price: "95", image: "https://i.pravatar.cc/150?img=12", rating: 4.7, categories: ["Все", "Депрессия"]),
    Specialist(id: "5", name: "Анна Вишневская", spec: "Арт-терапевт", bio: "Творчество как инструмент познания себя.", price: "75", image: "https://i.pravatar.cc/150?img=26", rating: 4.9, categories: ["Все", "Психосоматика"]),
    Specialist(id: "6", name: "Виктор Громов", spec: "Экзистенциальный терапевт", bio: "Поиск смысла жизни и кризисы.", price: "100", image: "https://i.pravatar.cc/150?img=13", rating: 4.6, categories: ["Все", "Карьера"]),
    Specialist(id: "7", name: "Ольга Суворова", spec: "Детский психолог", bio: "Работа с детьми и подростками.", price: "65", image: "https://i.pravatar.cc/150?img=35", rating: 4.8, categories: ["Все", "Семья"]),
  ];

  @override
  void initState() {
    super.initState();
    filteredSpecialists = List.from(specialists);
    _searchController.addListener(_applyFilters);
    _loadData();
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      favoriteIds = _prefs?.getStringList('favorite_psychologists') ?? [];

      // Загрузка состояния заявок
      final assignmentStr = _prefs?.getString('client_assignment');
      if (assignmentStr != null) {
        myAssignment = jsonDecode(assignmentStr);
      } else {
        myAssignment = null;
      }

      _applyFilters();
    });
  }

  Future<void> _updateAssignmentStatus(String status, {String? commentField, String? commentValue}) async {
    if (myAssignment != null) {
      myAssignment!['status'] = status;
      if (commentField != null && commentValue != null) {
        myAssignment![commentField] = commentValue;
      }
      if (status == 'none') {
        await _prefs?.remove('client_assignment');
        myAssignment = null;
      } else {
        await _prefs?.setString('client_assignment', jsonEncode(myAssignment));
      }
      setState(() {});
    }
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (favoriteIds.contains(id)) {
        favoriteIds.remove(id);
      } else {
        favoriteIds.add(id);
      }
      _prefs?.setStringList('favorite_psychologists', favoriteIds);
      _applyFilters();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      filteredSpecialists = specialists.where((s) {
        final nameMatch = s.name.toLowerCase().contains(_searchController.text.toLowerCase());
        bool categoryMatch = (selectedCategory == "❤️ Избранные")
            ? favoriteIds.contains(s.id)
            : (selectedCategory == "Все" || s.categories.contains(selectedCategory));

        final price = double.tryParse(s.price) ?? 0;
        final min = double.tryParse(_minPriceController.text) ?? 0;
        final max = double.tryParse(_maxPriceController.text) ?? 9999;
        return nameMatch && categoryMatch && price >= min && price <= max;
      }).toList();

      if (activeSort == SortType.priceLow) {
        filteredSpecialists.sort((a, b) => double.parse(a.price).compareTo(double.parse(b.price)));
      } else if (activeSort == SortType.priceHigh) {
        filteredSpecialists.sort((a, b) => double.parse(b.price).compareTo(double.parse(a.price)));
      } else if (activeSort == SortType.rating) {
        filteredSpecialists.sort((a, b) => b.rating.compareTo(a.rating));
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _minPriceController.clear();
      _maxPriceController.clear();
      selectedCategory = "Все";
      activeSort = SortType.none;
      filteredSpecialists = List.from(specialists);
    });
  }

  void _showFilterSheet() {
    _searchFocusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
              color: kDeepPurple,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30))
          ),
          child: Container(
            decoration: BoxDecoration(
                color: kWarmWhite.withOpacity(0.8),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30))
            ),
            padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 30),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(onPressed: () { _resetFilters(); Navigator.pop(context); }, icon: const Icon(Icons.refresh, color: kTextSecondary), label: const Text("Сбросить", style: TextStyle(color: kTextSecondary))),
                      IconButton(icon: const Icon(Icons.check_circle, color: kAccentPurple, size: 35), onPressed: () => Navigator.pop(context))
                    ],
                  ),
                  const Text("Сортировать", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _sortChip("Дешевле", SortType.priceLow, setModalState),
                      const SizedBox(width: 8),
                      _sortChip("Дороже", SortType.priceHigh, setModalState),
                      const SizedBox(width: 8),
                      _sortChip("Рейтинг", SortType.rating, setModalState),
                    ]),
                  ),
                  const SizedBox(height: 25),
                  const Text("Категория", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: allCategories.map((c) => ChoiceChip(
                      label: Text(c, style: TextStyle(color: selectedCategory == c ? kWarmWhite : kTextPrimary, fontWeight: selectedCategory == c ? FontWeight.bold : FontWeight.normal)),
                      selected: selectedCategory == c,
                      selectedColor: kAccentPurple,
                      backgroundColor: kAccentPurple.withOpacity(0.1),
                      onSelected: (v) { setModalState(() => selectedCategory = c); _applyFilters(); }
                  )).toList()),
                  const SizedBox(height: 25),
                  const Text("Цена", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _priceField("От", _minPriceController)),
                    const SizedBox(width: 15),
                    Expanded(child: _priceField("До", _maxPriceController))
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, SortType type, StateSetter setModalState) {
    final isSelected = activeSort == type;
    return ChoiceChip(
        label: Text(label, style: TextStyle(color: isSelected ? kWarmWhite : kTextPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        selected: isSelected,
        selectedColor: kAccentPurple,
        backgroundColor: kAccentPurple.withOpacity(0.1),
        onSelected: (v) { setModalState(() => activeSort = v ? type : SortType.none); _applyFilters(); }
    );
  }

  Widget _priceField(String prefix, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: kTextPrimary),
      onChanged: (v) => _applyFilters(),
      decoration: InputDecoration(
          prefixIcon: Padding(padding: const EdgeInsets.all(14), child: Text(prefix, style: const TextStyle(color: kTextSecondary))),
          filled: true,
          fillColor: kAccentPurple.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
      ),
    );
  }

  Future<void> _showCancelOrFinishDialog(bool isCancel) async {
    TextEditingController commentCtrl = TextEditingController();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(color: kDeepPurple, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: Container(
            decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.9), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
            padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isCancel ? "Отмена заявки" : "Завершение терапии", style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(isCancel ? "Почему вы решили отменить заявку?" : "Оставьте финальный отзыв или комментарий:", style: const TextStyle(color: kTextSecondary)),
                const SizedBox(height: 15),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: kTextPrimary),
                  decoration: InputDecoration(
                    hintText: "Напишите здесь...",
                    filled: true, fillColor: kDeepPurple.withOpacity(0.1),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: isCancel ? kWeekendRed : kAccentPurple, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    onPressed: () {
                      if (isCancel) {
                        _updateAssignmentStatus('none');
                      } else {
                        _updateAssignmentStatus('none');
                        // В реальном API здесь был бы статус canceled или finished отправлен на сервер
                      }
                      Navigator.pop(ctx);
                    },
                    child: Text(isCancel ? "Отменить заявку" : "Завершить работу", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
        )
    );
  }

  Widget _buildAssignmentStatusCard() {
    if (myAssignment == null) return const SizedBox.shrink();

    String status = myAssignment!['status'];
    String name = myAssignment!['psychologistName'];

    Color cardColor = kWarmWhite.withOpacity(0.8);
    IconData icon = Icons.info_outline;
    String title = "";
    String sub = "";
    Widget? actionBtn;

    if (status == 'requested') {
      icon = Icons.hourglass_empty;
      title = "Ожидание ответа";
      sub = "Заявка отправлена специалисту: $name";
      actionBtn = TextButton(onPressed: () => _showCancelOrFinishDialog(true), child: const Text("Отменить", style: TextStyle(color: kWeekendRed)));
    } else if (status == 'accepted') {
      icon = Icons.check_circle_outline;
      title = "Терапия активна";
      sub = "Ваш психолог: $name";
      actionBtn = TextButton(onPressed: () => _showCancelOrFinishDialog(false), child: const Text("Завершить", style: TextStyle(color: kTextSecondary)));
    } else if (status == 'rejected') {
      icon = Icons.cancel_outlined;
      title = "Заявка отклонена";
      sub = "Причина: ${myAssignment!['rejectComment'] ?? 'Нет мест'}";
      actionBtn = TextButton(onPressed: () => _updateAssignmentStatus('none'), child: const Text("Скрыть", style: TextStyle(color: kTextPrimary)));
    } else if (status == 'finished') {
      icon = Icons.flag_circle_outlined;
      title = "Работа завершена";
      sub = "Психолог завершил терапию.";
      actionBtn = TextButton(onPressed: () => _updateAssignmentStatus('none'), child: const Text("Ок", style: TextStyle(color: kTextPrimary)));
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAccentPurple.withOpacity(0.3), width: 1.5)
      ),
      child: Row(
        children: [
          Icon(icon, color: kAccentPurple, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary, fontSize: 16)),
                Text(sub, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
              ],
            ),
          ),
          if (actionBtn != null) actionBtn
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: kDeepPurple,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              floating: true,
              snap: true,
              elevation: 0,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              expandedHeight: 80,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.8), borderRadius: BorderRadius.circular(15)),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            style: const TextStyle(color: kTextPrimary),
                            decoration: InputDecoration(
                                hintText: "Поиск психолога...",
                                hintStyle: TextStyle(color: kTextPrimary.withOpacity(0.5)),
                                prefixIcon: const Icon(Icons.search, color: kTextPrimary, size: 22),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12)
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _showFilterSheet,
                        child: Container(
                            height: 48, width: 48,
                            decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.8), borderRadius: BorderRadius.circular(15)),
                            child: const Icon(Icons.tune, color: kTextPrimary)
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: Column(
            children: [
              _buildAssignmentStatusCard(),
              Expanded(
                child: filteredSpecialists.isEmpty
                    ? const Center(child: Text("Ничего не найдено", style: TextStyle(color: kTextSecondary)))
                    : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  itemCount: filteredSpecialists.length,
                  itemBuilder: (context, index) => _buildDoctorCard(filteredSpecialists[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorCard(Specialist doc) {
    bool isFav = favoriteIds.contains(doc.id);
    return GestureDetector(
      onTap: () {
        _searchFocusNode.unfocus();
        Navigator.push(
            context,
            MaterialPageRoute(builder: (c) => SpecialistProfileScreen(
              specialist: doc,
              isFavorite: isFav,
              onFavoriteToggle: () => _toggleFavorite(doc.id),
              onBooking: widget.onBookingConfirmed,
              onRatingUpdated: () => setState((){}),
              onRequestAssignment: () => _loadData(), // Обновляем при возврате
            ))
        ).then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kWarmWhite.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Hero(tag: doc.id, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(doc.image, width: 80, height: 80, fit: BoxFit.cover))),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: kTextPrimary)),
                  Text(doc.spec, style: const TextStyle(color: kAccentPurple, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                          Text(" ${doc.rating}", style: const TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _toggleFavorite(doc.id),
                            child: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? Colors.red : kTextSecondary,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      Text("${doc.price} BYN", style: const TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpecialistProfileScreen extends StatefulWidget {
  final Specialist specialist;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final Function(Map<String, dynamic>)? onBooking;
  final VoidCallback? onRatingUpdated;
  final VoidCallback? onRequestAssignment;

  const SpecialistProfileScreen({
    super.key, required this.specialist, required this.isFavorite,
    required this.onFavoriteToggle, this.onBooking, this.onRatingUpdated, this.onRequestAssignment
  });

  @override
  _SpecialistProfileScreenState createState() => _SpecialistProfileScreenState();
}

class _SpecialistProfileScreenState extends State<SpecialistProfileScreen> {
  late bool _localIsFavorite;

  @override
  void initState() {
    super.initState();
    _localIsFavorite = widget.isFavorite;
  }

  void _showRequestAssignmentDialog() {
    TextEditingController requestCtrl = TextEditingController();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(color: kDeepPurple, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: Container(
            decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.9), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
            padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Подача заявки", style: TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text("Напишите пару слов о том, что вас беспокоит. Это поможет специалисту подготовиться.", style: TextStyle(color: kTextSecondary, fontSize: 14)),
                const SizedBox(height: 15),
                TextField(
                  controller: requestCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: kTextPrimary),
                  decoration: InputDecoration(
                    hintText: "Опишите ваш запрос...",
                    filled: true, fillColor: kDeepPurple.withOpacity(0.1),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kAccentPurple, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      // Создаем объект заявки
                      final assignment = {
                        "id": DateTime.now().millisecondsSinceEpoch.toString(),
                        "clientName": "Тестовый Клиент", // В реальном АПИ берется из токена
                        "psychologistId": widget.specialist.id,
                        "psychologistName": widget.specialist.name,
                        "status": "requested",
                        "requestComment": requestCtrl.text.trim(),
                      };
                      await prefs.setString('client_assignment', jsonEncode(assignment));
                      if (widget.onRequestAssignment != null) widget.onRequestAssignment!();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Заявка успешно отправлена!")));
                    },
                    child: const Text("Отправить заявку", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                )
              ],
            ),
          ),
        )
    );
  }

  // Окна в стиле AuthScreen
  Future<bool?> _showStyledDialog(BuildContext context, String title, String content, String confirmText, Color confirmColor) {
    return showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '',
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, a1, a2) => Container(),
        transitionBuilder: (context, a1, a2, child) {
          return ScaleTransition(
              scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
              child: Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(40),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFF6F8FD), Color(0xFFF1EAFF)],
                        ),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
                      ),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: const TextStyle(color: Color(0xFF323045), fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                            const SizedBox(height: 15),
                            Text(content, style: const TextStyle(color: Color(0xFF706D8C), fontSize: 16), textAlign: TextAlign.center),
                            const SizedBox(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Назад", style: TextStyle(color: Color(0xFF706D8C), fontSize: 16))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: confirmColor,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    elevation: 4,
                                  ),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(confirmText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                              ],
                            )
                          ]
                      )
                  )
              )
          );
        }
    );
  }

  void _showRatingDialog() {
    showDialog(
        context: context,
        builder: (context) {
          int selectedStars = widget.specialist.rating.round();
          return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  backgroundColor: kWarmWhite,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text("Оцените специалиста", style: TextStyle(color: kTextPrimary), textAlign: TextAlign.center),
                  content: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      return IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          index < selectedStars ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: Colors.amber, size: 42,
                        ),
                        onPressed: () {
                          setDialogState(() => selectedStars = index + 1);
                        },
                      );
                    }),
                  ),
                  actionsAlignment: MainAxisAlignment.spaceBetween,
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Отмена", style: TextStyle(color: kTextSecondary))
                    ),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: kAccentPurple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () {
                          setState(() {
                            widget.specialist.rating = selectedStars.toDouble();
                          });
                          if (widget.onRatingUpdated != null) widget.onRatingUpdated!();
                          Navigator.pop(context);
                        },
                        child: const Text("Оценить", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    ),
                  ],
                );
              }
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepPurple,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(tag: widget.specialist.id, child: SizedBox(height: MediaQuery.of(context).size.height * 0.45, width: double.infinity, child: Image.network(widget.specialist.image, fit: BoxFit.cover))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.specialist.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: kWarmWhite)),
                                Text(
                                  widget.specialist.spec,
                                  style: TextStyle(fontSize: 16, color: kWarmWhite.withOpacity(0.8)),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _showRatingDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.22), borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [const Icon(Icons.star_rounded, color: Colors.amber, size: 20), const SizedBox(width: 4), Text(widget.specialist.rating.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: kWarmWhite))]),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Кнопка подачи заявки на терапию (State Machine Flow)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.assignment_ind_outlined, color: kWarmWhite),
                          label: const Text("Подать заявку на терапию", style: TextStyle(color: kWarmWhite, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: kWarmWhite, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                          ),
                          onPressed: _showRequestAssignmentDialog,
                        ),
                      ),

                      const SizedBox(height: 25),
                      const Text("О себе", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kWarmWhite)),
                      const SizedBox(height: 12),
                      Text(widget.specialist.bio, style: TextStyle(color: kWarmWhite.withOpacity(0.7), fontSize: 16, height: 1.6)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 50, left: 20,
            child: CircleAvatar(backgroundColor: Colors.black26, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))),
          ),
          Positioned(
            top: 50, right: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black26,
              child: IconButton(
                icon: Icon(
                  _localIsFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _localIsFavorite ? Colors.red : Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    _localIsFavorite = !_localIsFavorite;
                  });
                  widget.onFavoriteToggle();
                },
              ),
            ),
          ),
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                onPressed: () => _showBookingOverlay(context),
                style: ElevatedButton.styleFrom(backgroundColor: kAccentPurple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                child: Text("ЗАПИСАТЬСЯ • ${widget.specialist.price} BYN", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingOverlay(BuildContext context) {
    showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Booking",
        pageBuilder: (context, anim1, anim2) {
          return _BookingOverlay(spec: widget.specialist, onConfirmed: widget.onBooking, showStyledDialog: _showStyledDialog);
        }
    );
  }
}

class _BookingOverlay extends StatefulWidget {
  final Specialist spec;
  final Function(Map<String, dynamic>)? onConfirmed;
  final Future<bool?> Function(BuildContext, String, String, String, Color) showStyledDialog;

  const _BookingOverlay({required this.spec, this.onConfirmed, required this.showStyledDialog});

  @override
  State<_BookingOverlay> createState() => _BookingOverlayState();
}

class _BookingOverlayState extends State<_BookingOverlay> {
  DateTime visibleMonth = DateTime.now();
  DateTime? _selectedDate;
  String? selectedTime;
  int _calendarSlideDirection = 0;
  final DateTime now = DateTime.now();

  final List<String> times = [
    "09:00 - 10:00", "11:00 - 12:00", "12:30 - 13:30",
    "14:00 - 15:00", "15:30 - 16:30", "16:30 - 17:30",
    "18:00 - 19:00", "19:00 - 20:00", "20:30 - 21:30"
  ];

  Map<String, List<Map<String, dynamic>>> _bookedVisits = {};

  final List<String> _monthNames = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingBookings();
  }

  void _changeMonth({required int delta}) {
    setState(() {
      _calendarSlideDirection = delta > 0 ? 1 : -1;
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    });
  }

  Future<void> _loadExistingBookings() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    Map<String, List<Map<String, dynamic>>> visits = {};

    for (String key in allKeys) {
      if (key.startsWith("notes_")) {
        final data = prefs.getString(key);
        if (data != null) {
          try {
            final List<dynamic> notes = jsonDecode(data);
            List<Map<String, dynamic>> dailyVisits = [];
            for (var n in notes) {
              if (n['type'] == 'visit') {
                dailyVisits.add(n as Map<String, dynamic>);
              }
            }
            if (dailyVisits.isNotEmpty) {
              visits[key.replaceFirst("notes_", "")] = dailyVisits;
            }
          } catch (_) {}
        }
      }
    }
    setState(() => _bookedVisits = visits);
  }

  Future<void> _cancelBooking(String dateStr, String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    final String dateKey = "notes_$dateStr";
    final String? existingData = prefs.getString(dateKey);

    if (existingData != null) {
      try {
        List<dynamic> notes = jsonDecode(existingData);
        notes.removeWhere((n) => n['id'] == bookingId);

        if (notes.isEmpty) {
          await prefs.remove(dateKey);
        } else {
          await prefs.setString(dateKey, jsonEncode(notes));
        }
      } catch (_) {}
    }

    setState(() {
      _bookedVisits[dateStr]?.removeWhere((b) => b['id'] == bookingId);
      if (_bookedVisits[dateStr]?.isEmpty ?? false) {
        _bookedVisits.remove(dateStr);
      }
      selectedTime = null;
    });

    if (widget.onConfirmed != null) {
      widget.onConfirmed!({'date': dateStr, 'action': 'cancel'});
    }
  }

  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  List<DateTime> _buildGridDates(DateTime month) {
    final first = _firstDayOfMonth(month);
    final int startOffset = (first.weekday - 1);
    final DateTime gridStart = DateTime(month.year, month.month, 1).subtract(Duration(days: startOffset));
    final all = List<DateTime>.generate(42, (i) => gridStart.add(Duration(days: i)));
    final weeks = <List<DateTime>>[];
    for (int i = 0; i < 42; i += 7) { weeks.add(all.sublist(i, i + 7)); }
    weeks.removeWhere((week) => week.every((d) => d.month != month.month));
    return weeks.expand((w) => w).toList();
  }

  Future<void> _saveToCalendar(Map<String, dynamic> booking) async {
    final prefs = await SharedPreferences.getInstance();
    final String dateKey = "notes_${booking['date']}";
    final String? existingData = prefs.getString(dateKey);
    List<dynamic> notes = [];
    if (existingData != null) {
      try { notes = jsonDecode(existingData); } catch (_) { notes = []; }
    }
    notes.add({
      'id': "booking_${DateTime.now().millisecondsSinceEpoch}",
      'text': "💠 ${booking['specialist']}",
      'time': booking['time'],
      'createdAt': DateTime.now().toIso8601String(),
      'type': 'visit'
    });
    await prefs.setString(dateKey, jsonEncode(notes));
  }

  String _formatToYMD(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$year-$month-$day";
  }

  Widget _buildCalendarGrid({required Key key, required List<DateTime> gridDates, required double calendarHeight}) {
    final int totalCells = gridDates.length;
    final int rows = (totalCells / 7).ceil();
    final double cellHeight = calendarHeight / rows;

    return Container(
      key: key,
      child: SizedBox(
        height: calendarHeight,
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: (MediaQuery.of(context).size.width / 7) / cellHeight
          ),
          itemCount: totalCells,
          itemBuilder: (context, idx) {
            final d = gridDates[idx];
            final dateStr = _formatToYMD(d);
            final isOtherMonth = d.month != visibleMonth.month;
            final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
            final isWeekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
            final hasBooking = _bookedVisits.containsKey(dateStr) && _bookedVisits[dateStr]!.isNotEmpty;

            bool isSelected = _selectedDate != null && _selectedDate!.day == d.day && _selectedDate!.month == d.month && _selectedDate!.year == d.year;

            Color bg = Colors.transparent;
            if (isSelected) {
              bg = kAccentPurple;
            } else if (hasBooking) {
              bg = kAccentPurple.withOpacity(0.4);
            } else if (isToday) {
              bg = kWarmWhite.withOpacity(0.8);
            }

            Color textColor;
            if (isSelected) {
              textColor = Colors.white;
            } else if (isOtherMonth) {
              textColor = kTextSecondary.withOpacity(0.3);
            } else if (isWeekend) {
              textColor = kWeekendRed;
            } else {
              textColor = kTextPrimary;
            }

            return GestureDetector(
              onTap: () {
                if (isOtherMonth) {
                  setState(() => visibleMonth = DateTime(d.year, d.month));
                  Future.delayed(const Duration(milliseconds: 150), () => setState(() {
                    _selectedDate = d;
                    selectedTime = null;
                  }));
                } else {
                  setState(() {
                    _selectedDate = d;
                    selectedTime = null;
                  });
                }
              },
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                    child: Text(
                        d.day.toString().padLeft(2, '0'),
                        style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                            fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal
                        )
                    )
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gridDates = _buildGridDates(visibleMonth);
    const double calendarHeight = 230;

    String? selectedDateStr = _selectedDate != null ? _formatToYMD(_selectedDate!) : null;

    List<Map<String, dynamic>> currentBookings = selectedDateStr != null ? (_bookedVisits[selectedDateStr] ?? []) : [];
    List<String> bookedTimes = currentBookings.map((b) => b['time'].toString()).toList();
    List<String> availableTimes = times.where((t) => !bookedTimes.contains(t)).toList();

    return Scaffold(
      backgroundColor: kDeepPurple,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.close, color: kWarmWhite, size: 30),
                      onPressed: () => Navigator.pop(context)
                  ),
                  const Expanded(
                      child: Text("Выбор даты",
                          style: TextStyle(color: kWarmWhite, fontSize: 22, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center
                      )
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: kWarmWhite.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(icon: const Icon(Icons.chevron_left, color: kTextPrimary), onPressed: () { _changeMonth(delta: -1); }),
                        Expanded(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 1100),
                              transitionBuilder: (Widget child, Animation<double> anim) {
                                final offset = Tween<Offset>(begin: Offset(0.22 * _calendarSlideDirection, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                                return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: child)));
                              },
                              child: Text('${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}', key: ValueKey('${visibleMonth.month}_${visibleMonth.year}'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kTextPrimary)),
                            ),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.chevron_right, color: kTextPrimary), onPressed: () { _changeMonth(delta: 1); }),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'].map((d) {
                        final isWeekend = d == 'Сб' || d == 'Вс';
                        return Expanded(child: Center(child: Text(d, style: TextStyle(color: isWeekend ? kWeekendRed : kTextSecondary, fontWeight: FontWeight.w600))));
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onHorizontalDragEnd: (details) {
                        if (details.primaryVelocity == null) return;
                        if (details.primaryVelocity! < -200) { _changeMonth(delta: 1); }
                        else if (details.primaryVelocity! > 200) { _changeMonth(delta: -1); }
                      },
                      child: SizedBox(
                        height: calendarHeight,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 1100),
                          transitionBuilder: (Widget child, Animation<double> anim) {
                            final offset = Tween<Offset>(begin: Offset(0.18 * _calendarSlideDirection, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                            return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: child)));
                          },
                          child: _buildCalendarGrid(key: ValueKey<String>('grid_${visibleMonth.year}_${visibleMonth.month}_${gridDates.length}'), gridDates: gridDates, calendarHeight: calendarHeight),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            if (_selectedDate != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (currentBookings.isNotEmpty) ...[
                        const Text("Запланированные визиты", style: TextStyle(color: kWarmWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ...currentBookings.map((booking) {
                          String title = booking['text'].toString().replaceAll("Запись к психологу: ", "").replaceAll("💠 ", "");
                          if (title.contains(" в ")) title = title.split(" в ")[0];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kWarmWhite.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: kAccentPurple.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.event_available, color: kAccentPurple, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kTextPrimary)),
                                      const SizedBox(height: 4),
                                      Text("Сеанс: ${booking['time']}", style: const TextStyle(color: kTextSecondary, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel_outlined, color: kWeekendRed, size: 28),
                                  onPressed: () async {
                                    String timeStr = booking['time'].toString().split(" - ")[0];
                                    List<String> timeParts = timeStr.split(":");
                                    DateTime date = DateTime.parse(selectedDateStr!);
                                    DateTime appointmentTime = DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        int.tryParse(timeParts[0]) ?? 0,
                                        timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0
                                    );

                                    Duration diff = appointmentTime.difference(DateTime.now());
                                    bool isPenalty = diff.inHours < 24;

                                    // Окно 1: Подтверждение отмены
                                    final confirmCancel = await widget.showStyledDialog(
                                        context,
                                        "Отмена записи",
                                        "Вы действительно хотите отменить эту запись?",
                                        "Да, отменить",
                                        kWeekendRed
                                    );

                                    if (confirmCancel != true) return;

                                    // Окно 2: Предупреждение о неустойке (если меньше 24 часов)
                                    if (isPenalty) {
                                      if (!context.mounted) return;
                                      final confirmForfeit = await widget.showStyledDialog(
                                          context,
                                          "Внимание!",
                                          "До сеанса осталось менее 24 часов. За отмену может взиматься неустойка. Вы уверены, что хотите отменить?",
                                          "Согласен",
                                          kWeekendRed
                                      );

                                      if (confirmForfeit != true) return;
                                    }

                                    _cancelBooking(selectedDateStr!, booking['id']);
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 15),
                      ],

                      if (availableTimes.isNotEmpty) ...[
                        const Text("Доступное время", style: TextStyle(color: kWarmWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: kWarmWhite.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: availableTimes.map((t) => ChoiceChip(
                              label: Text(t, style: TextStyle(color: selectedTime == t ? Colors.white : kTextPrimary, fontWeight: FontWeight.w600)),
                              selected: selectedTime == t,
                              selectedColor: kAccentPurple,
                              backgroundColor: kWarmWhite,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              onSelected: (v) => setState(() => selectedTime = v ? t : null),
                            )).toList(),
                          ),
                        )
                      ] else ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text("Нет доступного времени на этот день", style: TextStyle(color: kWarmWhite, fontSize: 16)),
                          ),
                        )
                      ]
                    ],
                  ),
                ),
              ),

            if (_selectedDate != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity, height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: selectedTime != null ? kAccentPurple : Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                    ),
                    onPressed: selectedTime != null ? () async {
                      final data = {
                        'specialist': "${widget.spec.name} в $selectedTime",
                        'date': _formatToYMD(_selectedDate!),
                        'time': selectedTime,
                      };
                      await _saveToCalendar(data);
                      if (widget.onConfirmed != null) widget.onConfirmed!(data);

                      if (mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    } : null,
                    child: const Text("ПОДТВЕРДИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}