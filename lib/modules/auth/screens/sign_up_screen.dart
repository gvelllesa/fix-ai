import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import 'sign_in_screen.dart';
import '../../chat/screens/chat_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({Key? key}) : super(key: key);

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authController = AuthController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _authController.dispose();
    super.dispose();
  }

  void _signUp() async {
    if (_formKey.currentState!.validate()) {
      final success = await _authController.signUp(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (success) {
        if (mounted) {
          // Navigate to ChatScreen safely upon successful authentication
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const ChatScreen(
                carProfile: {
                  'brand': 'Unknown',
                  'model': 'Vehicle',
                  'id': 'new-user-profile',
                },
              ),
            ),
          );
        }
      } else {
        if (mounted && _authController.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_authController.errorMessage!),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _authController,
          builder: (context, _) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.person_add_alt_1, size: 80, color: Colors.blueAccent),
                      const SizedBox(height: 24),
                      const Text(
                        'Create Account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sign up to access advanced AI diagnostics',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.white54),
                      ),
                      const SizedBox(height: 48),
                      TextFormField(
                        controller: _emailController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF1E1E1E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.email, color: Colors.white54),
                        ),
                        validator: (value) => value == null || !value.contains('@') ? 'Enter a valid email' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF1E1E1E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.lock, color: Colors.white54),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) => value == null || value.length < 6 ? 'Password must be at least 6 characters' : null,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _authController.isLoading ? null : _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _authController.isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Sign Up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const SignInScreen()),
                          );
                        },
                        child: const Text('Already have an account? Sign In', style: TextStyle(color: Colors.blueAccent)),
                      ),
                      const SizedBox(height: 24),
                      // Social Sign-In Divider
                      Row(
                        children: [
                          Expanded(child: Container(height: 1, color: Colors.white12)),
                          const Flexible(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'ან გააგრძელეთ შემდეგით', 
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          Expanded(child: Container(height: 1, color: Colors.white12)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Social Sign-In Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Google Sign-In
                          GestureDetector(
                            onTap: () => _authController.signInWithGoogle(),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12, width: 1),
                              ),
                              child: Center(
                                child: Text('G', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, foreground: Paint()..shader = const LinearGradient(colors: [Color(0xFF4285F4), Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853)]).createShader(const Rect.fromLTWH(0, 0, 24, 24)))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // Apple Sign-In
                          GestureDetector(
                            onTap: () => _authController.signInWithApple(),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12, width: 1),
                              ),
                              child: const Center(
                                child: Icon(Icons.apple, color: Colors.white, size: 32),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
