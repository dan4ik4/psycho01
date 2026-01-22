import 'package:flutter/material.dart';

enum SortType { none, priceLow, priceHigh, rating }

// Основной цвет приложения — нежный фиолетовый
const Color kPrimarySoftPurple = Color(0xFF9D8DF1);

class Specialist {
  final String id;
  final String name;
  final String bio;
  final String spec;
  final String price;
  final String image;
  final double rating;
  final List<String> categories;

  Specialist({
    required this.id, required this.name, required this.bio,
    required this.spec, required this.price, required this.image,
    required this.rating, required this.categories,
  });
}

class SpecialistListScreen extends StatefulWidget {
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

  void _toggleFavorite(String id) {
    setState(() {
      favoriteIds.contains(id) ? favoriteIds.remove(id) : favoriteIds.add(id);
      _applyFilters();
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
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 50),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(onPressed: () { _resetFilters(); Navigator.pop(context); }, icon: const Icon(Icons.refresh, color: Colors.grey), label: const Text("Сбросить", style: TextStyle(color: Colors.grey))),
                  IconButton(icon: const Icon(Icons.check_circle, color: kPrimarySoftPurple, size: 35), onPressed: () => Navigator.pop(context))
                ],
              ),
              const Text("Сортировать", style: TextStyle(fontWeight: FontWeight.bold)),
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
              const Text("Категория", style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 8, children: allCategories.map((c) => ChoiceChip(
                  label: Text(c),
                  selected: selectedCategory == c,
                  selectedColor: kPrimarySoftPurple,
                  labelStyle: TextStyle(color: selectedCategory == c ? Colors.white : Colors.black87),
                  onSelected: (v) { setModalState(() => selectedCategory = c); _applyFilters(); }
              )).toList()),
              const SizedBox(height: 25),
              Row(children: [Expanded(child: _priceField("От", _minPriceController)), const SizedBox(width: 15), Expanded(child: _priceField("До", _maxPriceController))]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, SortType type, StateSetter setModalState) {
    final isSelected = activeSort == type;
    return ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: kPrimarySoftPurple,
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
        onSelected: (v) { setModalState(() => activeSort = v ? type : SortType.none); _applyFilters(); }
    );
  }

  Widget _priceField(String prefix, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: (v) => _applyFilters(),
      decoration: InputDecoration(
          prefixIcon: Padding(padding: const EdgeInsets.all(14), child: Text(prefix, style: const TextStyle(color: Colors.grey))),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FE),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              floating: true,
              snap: true,
              elevation: 0,
              backgroundColor: kPrimarySoftPurple, // Используем нежный фиолетовый
              expandedHeight: 70,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            decoration: const InputDecoration(
                                hintText: "Поиск психолога...",
                                prefixIcon: Icon(Icons.search, color: kPrimarySoftPurple, size: 22),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 12)
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _showFilterSheet,
                        child: Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(15)),
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
              ? const Center(child: Text("Ничего не найдено", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
            padding: const EdgeInsets.only(top: 10, bottom: 100),
            itemCount: filteredSpecialists.length,
            itemBuilder: (context, index) => _buildDoctorCard(filteredSpecialists[index]),
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
        Navigator.push(context, MaterialPageRoute(builder: (c) => SpecialistProfileScreen(specialist: doc, isFavorite: isFav, onFavoriteToggle: () => _toggleFavorite(doc.id))));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))]),
        child: Row(
          children: [
            Hero(tag: doc.id, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(doc.image, width: 80, height: 80, fit: BoxFit.cover))),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  Text(doc.spec, style: const TextStyle(color: kPrimarySoftPurple, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          Text(" ${doc.rating}", style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _toggleFavorite(doc.id),
                            child: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : Colors.grey[400], size: 20),
                          ),
                        ],
                      ),
                      Text("${doc.price} BYN", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
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

  SpecialistProfileScreen({required this.specialist, required this.isFavorite, required this.onFavoriteToggle});

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

  @override
  Widget build(BuildContext context) {
    double bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(tag: widget.specialist.id, child: Container(height: MediaQuery.of(context).size.height * 0.45, width: double.infinity, child: Image.network(widget.specialist.image, fit: BoxFit.cover))),
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
                                Text(widget.specialist.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                                Text(widget.specialist.spec, style: const TextStyle(fontSize: 16, color: kPrimarySoftPurple, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: kPrimarySoftPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                            child: Row(children: [const Icon(Icons.star, color: kPrimarySoftPurple, size: 20), const SizedBox(width: 4), Text(widget.specialist.rating.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimarySoftPurple))]),
                          )
                        ],
                      ),
                      const SizedBox(height: 30),
                      const Text("О себе", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text(widget.specialist.bio, style: const TextStyle(color: Colors.black54, fontSize: 16, height: 1.6)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(backgroundColor: Colors.white, child: IconButton(icon: const Icon(Icons.arrow_back, color: kPrimarySoftPurple), onPressed: () => Navigator.pop(context))),
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: IconButton(
                    icon: Icon(_localIsFavorite ? Icons.favorite : Icons.favorite_border, color: _localIsFavorite ? Colors.red : kPrimarySoftPurple),
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
            bottom: bottomInset > 0 ? bottomInset - 30 : 25, // Строка регулировки высоты кнопки записи
            left: 20,
            right: 20,
            child: Container(
              height: 60,
              decoration: BoxDecoration(boxShadow: [BoxShadow(color: kPrimarySoftPurple.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: kPrimarySoftPurple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                child: Text("ЗАПИСАТЬСЯ • ${widget.specialist.price} BYN", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}