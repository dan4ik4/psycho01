import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/widgets/oakle_notice.dart';
import '../core/auth/token_storage.dart';
import '../features/profile/data/profile_repository.dart';

class ProfileScreen extends StatefulWidget {
  final ApiClient apiClient;

  const ProfileScreen({super.key, required this.apiClient});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileRepository _repository;
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _specialization = TextEditingController();
  final _licenseNumber = TextEditingController();
  final _bio = TextEditingController();
  final _experienceYears = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String _email = '';
  String _userId = '';
  String? _photoPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = ProfileRepository(
      apiClient: widget.apiClient,
      tokenStorage: TokenStorage(),
    );
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _repository.fetchUserProfile();
      final psychologist = await _repository.fetchPsychologistProfile();
      final prefs = await SharedPreferences.getInstance();
      final userId = user['id']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _firstName.text = user['first_name']?.toString() ?? '';
        _lastName.text = user['last_name']?.toString() ?? '';
        _email = user['email']?.toString() ?? '';
        _userId = userId;
        _photoPath = prefs.getString('psychologist_photo_$userId');
        _specialization.text = psychologist['specialization']?.toString() ?? '';
        _licenseNumber.text = psychologist['license_number']?.toString() ?? '';
        _bio.text = psychologist['bio']?.toString() ?? '';
        _experienceYears.text =
            psychologist['experience_years']?.toString() ?? '';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            'Не удалось загрузить профиль. Проверьте подключение и попробуйте ещё раз.';
        _isLoading = false;
      });
    }
  }

  Future<void> _choosePhoto() async {
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (selected == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('psychologist_photo_$_userId', selected.path);
    setState(() => _photoPath = selected.path);
    showOakleNotice(context, 'Фото выбрано на этом устройстве');
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _repository.updateUserProfile({
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
      });
      await _repository.updatePsychologistProfile({
        'specialization': _specialization.text.trim(),
        'license_number': _licenseNumber.text.trim(),
        'bio': _bio.text.trim(),
        'experience_years': int.parse(_experienceYears.text.trim()),
      });
      if (!mounted) return;
      showOakleNotice(context, 'Профиль сохранён');
    } catch (error) {
      if (!mounted) return;
      showOakleNotice(
        context,
        friendlyApiError(
          error,
          fallback: 'Не удалось сохранить профиль. Проверьте заполненные поля.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _specialization.dispose();
    _licenseNumber.dispose();
    _bio.dispose();
    _experienceYears.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFB0A6E8),
      appBar: AppBar(
        title: const Text('Профиль психолога'),
        backgroundColor: const Color(0xFFB0A6E8),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _error = null;
                        });
                        _loadProfile();
                      },
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 46,
                          backgroundColor: const Color(0xFFE8E4F7),
                          backgroundImage:
                              _photoPath != null &&
                                  File(_photoPath!).existsSync()
                              ? FileImage(File(_photoPath!))
                              : null,
                          child:
                              _photoPath == null ||
                                  !File(_photoPath!).existsSync()
                              ? const Icon(Icons.person_outline, size: 42)
                              : null,
                        ),
                        TextButton.icon(
                          onPressed: _choosePhoto,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Добавить фото'),
                        ),
                        const Text(
                          'Фото пока доступно только на этом устройстве: серверный API загрузки фото не опубликован.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF706D8C),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _email,
                    style: const TextStyle(color: Color(0xFF706D8C)),
                  ),
                  const SizedBox(height: 18),
                  _field(_firstName, 'Имя'),
                  _field(_lastName, 'Фамилия'),
                  _field(_specialization, 'Специализация', maxLength: 150),
                  _field(
                    _licenseNumber,
                    'Номер лицензии',
                    maxLength: 100,
                    required: false,
                  ),
                  _field(
                    _experienceYears,
                    'Опыт работы (полных лет)',
                    numeric: true,
                  ),
                  _field(_bio, 'О себе', maxLines: 5, required: false),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Сохранить изменения'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    int? maxLength,
    bool numeric = false,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (required && text.isEmpty) return 'Заполните поле';
          if (numeric &&
              text.isNotEmpty &&
              (int.tryParse(text) == null || int.parse(text) < 0))
            return 'Введите целое число от 0';
          return null;
        },
      ),
    );
  }
}
