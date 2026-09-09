import 'package:flutter/material.dart';

import '../models/emergency_contact.dart';
import '../models/user_profile.dart';
import '../services/emergency_contact_repository.dart';
import '../services/onboarding_repository.dart';
import '../services/user_profile_repository.dart';

/// Minimal setup form for Phase 2 Step 6. Collects exactly what the
/// existing Phase 2 models need: user name, preferred language, and
/// one emergency contact (always saved as primary — multi-contact
/// management is a later phase).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  String _preferredLanguage = 'en';

  final _profileRepo = UserProfileRepository();
  final _contactRepo = EmergencyContactRepository();
  final _onboardingRepo = OnboardingRepository();

  UserProfile? _existingProfile;
  EmergencyContact? _existingPrimaryContact;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    // Fire-and-forget, but with its own error handling so a failure
    // here can't throw an unhandled exception during widget init.
    _markOnboardingStarted();

    _existingProfile = _profileRepo.load();
    if (_existingProfile != null) {
      _nameController.text = _existingProfile!.name;
      _preferredLanguage = _existingProfile!.preferredLanguage;
    }

    _existingPrimaryContact = _contactRepo.loadPrimary();
    if (_existingPrimaryContact != null) {
      _contactNameController.text = _existingPrimaryContact!.name;
      _contactPhoneController.text = _existingPrimaryContact!.phoneNumber;
    }
  }

  Future<void> _markOnboardingStarted() async {
    try {
      await _onboardingRepo.markStarted();
    } catch (e) {
      debugPrint('[NeuralSafe] Failed to mark onboarding started: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Preserve the original createdAt when editing an existing
      // profile; only stamp DateTime.now() for a brand-new profile.
      final profile = _existingProfile != null
          ? _existingProfile!.copyWith(
              name: _nameController.text.trim(),
              preferredLanguage: _preferredLanguage,
            )
          : UserProfile(
              name: _nameController.text.trim(),
              preferredLanguage: _preferredLanguage,
              createdAt: DateTime.now(),
            );
      await _profileRepo.save(profile);

      final contact = _existingPrimaryContact != null
          ? _existingPrimaryContact!.copyWith(
              name: _contactNameController.text.trim(),
              phoneNumber: _contactPhoneController.text.trim(),
              isPrimary: true,
            )
          : EmergencyContact.create(
              name: _contactNameController.text.trim(),
              phoneNumber: _contactPhoneController.text.trim(),
              isPrimary: true,
            );
      await _contactRepo.save(contact);

      await _onboardingRepo.markComplete();

      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Your Info',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Your name'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _preferredLanguage,
              decoration:
                  const InputDecoration(labelText: 'Preferred language'),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'ur', child: Text('Urdu')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _preferredLanguage = value);
                }
              },
            ),
            const SizedBox(height: 24),
            const Text('Emergency Contact',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contactNameController,
              decoration: const InputDecoration(labelText: 'Contact name'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Contact name is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contactPhoneController,
              decoration:
                  const InputDecoration(labelText: 'Contact phone number'),
              keyboardType: TextInputType.phone,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Contact phone number is required'
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'This contact is automatically set as primary.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _handleSave,
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
