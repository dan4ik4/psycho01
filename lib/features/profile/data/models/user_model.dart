class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String role;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email'] ?? '',
      fullName: [json['first_name'], json['last_name']]
          .where((value) => value != null && value.toString().trim().isNotEmpty)
          .join(' '),
      role: json['is_psychologist'] == true ? 'specialist' : 'client',
    );
  }
}
