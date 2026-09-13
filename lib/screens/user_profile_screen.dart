import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';

/// Profile setup/edit screen. Strain (and eventually Healthspan) read
/// from [UserProfileService] instead of a hardcoded default age — this
/// is where that data actually gets entered.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  DateTime? _dob;
  final _ageController = TextEditingController();
  final _maxHrController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  String? _sex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _maxHrController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await UserProfileService.instance.loadProfile();
    if (!mounted) return;
    setState(() {
      _dob = profile.dateOfBirth;
      _ageController.text = profile.manualAge?.toString() ?? '';
      _maxHrController.text = profile.maxHeartRateBpm?.round().toString() ?? '';
      _heightController.text = profile.heightCm?.round().toString() ?? '';
      _weightController.text = profile.weightKg?.round().toString() ?? '';
      _sex = profile.biologicalSex;
      _loading = false;
    });
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final profile = UserProfile(
      dateOfBirth: _dob,
      manualAge: _dob == null ? int.tryParse(_ageController.text) : null,
      maxHeartRateBpm: double.tryParse(_maxHrController.text),
      heightCm: double.tryParse(_heightController.text),
      weightKg: double.tryParse(_weightController.text),
      biologicalSex: _sex,
    );
    await UserProfileService.instance.saveProfile(profile);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.dashboardBackground),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.chevron_left_rounded, color: AppColors.cyan, size: 28)),
                          const Text('Your Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Used for HR-zone and Strain math \u2014 the more accurate this is, the more accurate those numbers are.',
                          style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _FieldLabel('Date of Birth (preferred)'),
                      InkWell(
                        onTap: _pickDob,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, color: AppColors.cyan, size: 16),
                              const SizedBox(width: 10),
                              Text(
                                _dob != null ? '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}' : 'Not set',
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _FieldLabel('Or enter age directly'),
                      _NumberField(controller: _ageController, hint: 'e.g. 32', enabled: _dob == null, suffix: 'yrs'),
                      if (_dob != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('Age field is disabled while a date of birth is set.', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
                        ),
                      const SizedBox(height: 20),
                      const _FieldLabel('Known Max Heart Rate (optional)'),
                      _NumberField(controller: _maxHrController, hint: 'Leave blank to estimate from age', suffix: 'bpm'),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('Height'),
                                _NumberField(controller: _heightController, hint: 'e.g. 175', suffix: 'cm'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('Weight'),
                                _NumberField(controller: _weightController, hint: 'e.g. 70', suffix: 'kg'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('Biological Sex (optional)'),
                      Wrap(
                        spacing: 8,
                        children: [
                          _SexChip(label: 'Female', value: 'female', groupValue: _sex, onSelected: (v) => setState(() => _sex = v)),
                          _SexChip(label: 'Male', value: 'male', groupValue: _sex, onSelected: (v) => setState(() => _sex = v)),
                          _SexChip(label: 'Prefer not to say', value: 'unspecified', groupValue: _sex, onSelected: (v) => setState(() => _sex = v)),
                        ],
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: AppColors.navyDeep,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navyDeep))
                              : const Text('Save Profile', style: TextStyle(fontWeight: FontWeight.w700)),
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String suffix;
  final bool enabled;

  const _NumberField({required this.controller, required this.hint, required this.suffix, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      style: TextStyle(color: enabled ? AppColors.textPrimary : AppColors.textDim, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}

class _SexChip extends StatelessWidget {
  final String label;
  final String value;
  final String? groupValue;
  final ValueChanged<String> onSelected;

  const _SexChip({required this.label, required this.value, required this.groupValue, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final selected = groupValue == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      backgroundColor: Colors.white.withOpacity(0.06),
      selectedColor: AppColors.cyan.withOpacity(0.25),
      labelStyle: TextStyle(color: selected ? AppColors.cyanBright : AppColors.textSecondary, fontSize: 12),
      side: BorderSide(color: selected ? AppColors.cyan : Colors.transparent),
    );
  }
}
