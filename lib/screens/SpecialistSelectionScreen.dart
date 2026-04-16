import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum SortType { none, priceLow, priceHigh, rating }

// Цветовая палитра SoulBuddy
const Color kDeepPurple = Color(0xFF2D1B4E);
const Color kAccentPurple = Color(0xFF9575CD);
const Color kWarmWhite = Color(0xFFFFF9F2);

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
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      favoriteIds = _prefs?.getStringList('favorite_psychologists') ?? [];
      _applyFilters();
    });
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
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 50),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(onPressed: () { _resetFilters(); Navigator.pop(context); }, icon: const Icon(Icons.refresh, color: Colors.white60), label: const Text("Сбросить", style: TextStyle(color: Colors.white60))),
                  IconButton(icon: const Icon(Icons.check_circle, color: Colors.white, size: 35), onPressed: () => Navigator.pop(context))
                ],
              ),
              const Text("Сортировать", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              const Text("Категория", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: allCategories.map((c) => ChoiceChip(
                  label: Text(c, style: TextStyle(color: selectedCategory == c ? kDeepPurple : Colors.white, fontWeight: selectedCategory == c ? FontWeight.bold : FontWeight.normal)),
                  selected: selectedCategory == c,
                  selectedColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  onSelected: (v) { setModalState(() => selectedCategory = c); _applyFilters(); }
              )).toList()),
              const SizedBox(height: 25),
              Row(children: [
                Expanded(child: _priceField("От", _minPriceController)),
                const SizedBox(width: 15),
                Expanded(child: _priceField("До", _maxPriceController))
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, SortType type, StateSetter setModalState) {
    final isSelected = activeSort == type;
    return ChoiceChip(
        label: Text(label, style: TextStyle(color: isSelected ? kDeepPurple : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        selected: isSelected,
        selectedColor: Colors.white,
        backgroundColor: Colors.white.withOpacity(0.05),
        onSelected: (v) { setModalState(() => activeSort = v ? type : SortType.none); _applyFilters(); }
    );
  }

  Widget _priceField(String prefix, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      onChanged: (v) => _applyFilters(),
      decoration: InputDecoration(
          prefixIcon: Padding(padding: const EdgeInsets.all(14), child: Text(prefix, style: const TextStyle(color: Colors.white54))),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: kDeepPurple,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [kDeepPurple, kWarmWhite], stops: [0.6, 1.0],
            ),
          ),
          child: NestedScrollView(
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
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15)),
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                  hintText: "Поиск психолога...",
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                  prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 22),
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
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15)),
                              child: const Icon(Icons.tune, color: Colors.white)
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: filteredSpecialists.isEmpty
                ? Center(child: Text("Ничего не найдено", style: TextStyle(color: Colors.white.withOpacity(0.5))))
                : ListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 100),
              itemCount: filteredSpecialists.length,
              itemBuilder: (context, index) => _buildDoctorCard(filteredSpecialists[index]),
            ),
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
            ))
        ).then((_) => setState((){}));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Hero(tag: doc.id, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(doc.image, width: 80, height: 80, fit: BoxFit.cover))),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
                  Text(doc.spec, style: const TextStyle(color: kAccentPurple, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          Text(" ${doc.rating}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _toggleFavorite(doc.id),
                            child: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : Colors.white38, size: 20),
                          ),
                        ],
                      ),
                      Text("${doc.price} BYN", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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

  const SpecialistProfileScreen({
    super.key, required this.specialist, required this.isFavorite,
    required this.onFavoriteToggle, this.onBooking, this.onRatingUpdated
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

  void _showRatingDialog() {
    showDialog(
        context: context,
        builder: (context) {
          int selectedStars = widget.specialist.rating.round();
          return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  backgroundColor: kDeepPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text("Оцените специалиста", style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  content: Row( // ФИКС: Row вместо Wrap для стабильности в один ряд
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      return IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          index < selectedStars ? Icons.star : Icons.star_border,
                          color: Colors.amber, size: 36,
                        ),
                        onPressed: () {
                          setDialogState(() => selectedStars = index + 1);
                        },
                      );
                    }),
                  ),
                  actionsAlignment: MainAxisAlignment.spaceBetween,
                  actions: [
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () {
                          setState(() {
                            widget.specialist.rating = selectedStars.toDouble();
                          });
                          if (widget.onRatingUpdated != null) widget.onRatingUpdated!();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Спасибо за вашу оценку!"), backgroundColor: kAccentPurple));
                        },
                        child: const Text("Оценить", style: TextStyle(color: kDeepPurple, fontWeight: FontWeight.bold))
                    ),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Отмена", style: TextStyle(color: Colors.white54))
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
    double bottomInset = MediaQuery.of(context).padding.bottom;

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
                                Text(widget.specialist.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                                Text(widget.specialist.spec, style: const TextStyle(fontSize: 16, color: kAccentPurple, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _showRatingDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
                              child: Row(children: [const Icon(Icons.star, color: Colors.amber, size: 20), const SizedBox(width: 4), Text(widget.specialist.rating.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))]),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 30),
                      const Text("О себе", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 12),
                      Text(widget.specialist.bio, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, height: 1.6)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 50, left: 20, right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(backgroundColor: kDeepPurple.withOpacity(0.6), child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))),
                CircleAvatar(
                  backgroundColor: kDeepPurple.withOpacity(0.6),
                  child: IconButton(
                    icon: Icon(_localIsFavorite ? Icons.favorite : Icons.favorite_border, color: _localIsFavorite ? Colors.red : Colors.white),
                    onPressed: () {
                      setState(() => _localIsFavorite = !_localIsFavorite);
                      widget.onFavoriteToggle();
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: bottomInset > 0 ? bottomInset + 10 : 25,
            left: 20, right: 20,
            child: Container(
              height: 60,
              decoration: BoxDecoration(boxShadow: [BoxShadow(color: kDeepPurple.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))]),
              child: ElevatedButton(
                onPressed: () => _showBookingSheet(context),
                style: ElevatedButton.styleFrom(backgroundColor: kAccentPurple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                child: Text("ЗАПИСАТЬСЯ • ${widget.specialist.price} BYN", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => _BookingSheet(spec: widget.specialist, onConfirmed: widget.onBooking),
    );
  }
}

class _BookingSheet extends StatefulWidget {
  final Specialist spec;
  final Function(Map<String, dynamic>)? onConfirmed;
  const _BookingSheet({required this.spec, this.onConfirmed});

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  DateTime? selDate;
  String? selTime;
  final List<String> times = ["09:00", "11:00", "14:00", "16:30", "19:00"];
  final List<String> daysRu = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

  // ФИКС: Сохранение записи в календарь (через SharedPreferences)
  Future<void> _saveToCalendar(Map<String, dynamic> booking) async {
    final prefs = await SharedPreferences.getInstance();
    final String dateKey = "notes_${booking['date']}";
    final String? existingData = prefs.getString(dateKey);
    List<dynamic> notes = [];
    if (existingData != null) {
      try { notes = jsonDecode(existingData); } catch (_) { notes = []; }
    }
    notes.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': "Запись: ${booking['specialist']} (${booking['time']})",
      'createdAt': DateTime.now().toIso8601String(),
      'type': 'visit'
    });
    await prefs.setString(dateKey, jsonEncode(notes));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: 25, right: 25, top: 25, bottom: MediaQuery.of(context).viewInsets.bottom + 40),
      decoration: const BoxDecoration(color: kDeepPurple, borderRadius: BorderRadius.vertical(top: Radius.circular(35))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 20),
          const Text("Выберите дату", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          SizedBox(
            height: 95,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              itemBuilder: (context, i) {
                DateTime d = DateTime.now().add(Duration(days: i));
                bool isS = selDate?.day == d.day && selDate?.month == d.month;
                String dayStr = daysRu[d.weekday - 1];

                return GestureDetector(
                  onTap: () => setState(() => selDate = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 70, margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                        color: isS ? Colors.white : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isS ? Colors.white : Colors.white10)
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(dayStr, style: TextStyle(color: isS ? kDeepPurple : Colors.white38, fontSize: 12, fontWeight: isS ? FontWeight.bold : FontWeight.normal)),
                      const SizedBox(height: 4),
                      Text("${d.day}", style: TextStyle(color: isS ? kDeepPurple : Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 30),
          const Text("Доступное время", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Wrap(spacing: 10, runSpacing: 10, children: times.map((t) => ChoiceChip(
            label: Text(t, style: TextStyle(color: selTime == t ? kDeepPurple : Colors.white, fontWeight: FontWeight.bold)),
            selected: selTime == t,
            selectedColor: Colors.white, // ФИКС: Тёмный текст на белом чипсе
            backgroundColor: Colors.white.withOpacity(0.05),
            onSelected: (v) => setState(() => selTime = v ? t : null),
          )).toList()),
          const SizedBox(height: 30),

          SizedBox(width: double.infinity, height: 60, child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: (selDate != null && selTime != null) ? Colors.white : Colors.white10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
            ),
            onPressed: (selDate != null && selTime != null) ? () async {
              final bookingData = {
                'specialist': widget.spec.name,
                'date': DateFormat('yyyy-MM-dd').format(selDate!),
                'time': selTime,
                'type': 'visit'
              };

              await _saveToCalendar(bookingData); // ФИКС: Сохранение
              if (widget.onConfirmed != null) {
                widget.onConfirmed!(bookingData);
              }

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Запись к ${widget.spec.name} на $selTime добавлена в календарь!"), backgroundColor: Colors.green)
              );
            } : null,
            child: Text("ПОДТВЕРДИТЬ ЗАПИСЬ", style: TextStyle(color: (selDate != null && selTime != null) ? kDeepPurple : Colors.white54, fontWeight: FontWeight.bold)),
          ))
        ],
      ),
    );
  }
}