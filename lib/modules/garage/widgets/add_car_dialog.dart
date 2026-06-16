import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/vin_decoder_service.dart';
import 'package:flutter/services.dart';
import '../screens/vin_scanner_overlay.dart';

class AddCarDialog extends StatefulWidget {
  const AddCarDialog({Key? key}) : super(key: key);

  @override
  State<AddCarDialog> createState() => _AddCarDialogState();
}

class _AddCarDialogState extends State<AddCarDialog> {
  final _vinController = TextEditingController();
  bool _isSaving = false;

  Future<void> _openScanner() async {
    final scannedVin = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const VinScannerOverlay()),
    );
    if (scannedVin != null && scannedVin.isNotEmpty) {
      setState(() {
        _vinController.text = scannedVin;
      });
    }
  }

  Future<void> _saveVehicle() async {
    final vin = _vinController.text.trim();
    if (vin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('VIN cannot be empty')));
      return;
    }

    setState(() => _isSaving = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      // Attempt to decode VIN automatically before saving
      final decodedData = await VinDecoderService.decodeVin(vin);
      
      if (decodedData == null) {
        throw Exception("Invalid VIN or unable to decode vehicle details.");
      }

      final make = decodedData['make'] ?? 'Unknown Make';
      final model = decodedData['model'] ?? 'Unknown Model';
      final yearStr = decodedData['year'] ?? '0';
      final year = int.tryParse(yearStr) ?? 0;
      final engineStr = decodedData['engine'];
      final engineType = (engineStr != null && engineStr != 'nullL' && engineStr != 'L') ? engineStr : '';

      await Supabase.instance.client.from('garage').insert({
        'vin': vin,
        'make': make,
        'model': model,
        'year': year,
        'engine_type': engineType,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added \$year \$make \$model!')));
        Navigator.of(context).pop(true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB Error: \${e.message}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('\$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _vinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner, color: Color(0xFF0F62FE), size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Add Vehicle',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter or scan your 17-digit VIN. We will automatically decode your vehicle profile.',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    
                    // Sleek VIN TextField
                    TextFormField(
                      controller: _vinController,
                      style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w600),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(17),
                        FilteringTextInputFormatter.allow(RegExp(r'[A-HJ-NPR-Z0-9]')),
                      ],
                      decoration: InputDecoration(
                        hintText: '17-DIGIT VIN',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), letterSpacing: 2),
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF0F62FE), width: 2),
                        ),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Material(
                            color: const Color(0xFF0F62FE).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              onTap: _openScanner,
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Icon(Icons.camera_alt, color: Color(0xFF0F62FE)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              
              const Divider(height: 1, color: Colors.white10),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveVehicle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F62FE),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    child: _isSaving 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('DECODE & SAVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
