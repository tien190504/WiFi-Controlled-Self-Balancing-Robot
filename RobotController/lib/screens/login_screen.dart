import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/mqtt_service.dart';
import 'device_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _serverController = TextEditingController();

  bool _isLoading = false;
  bool _isLoginMode = true;

  @override
  void initState() {
    super.initState();
    final api = ApiService();
    _serverController.text = api.serverHost;
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
    });

    final api = ApiService();
    final mqtt = MqttService();
    bool success = false;

    try {
      await api.updateServerConfig(_serverController.text.trim());
      await mqtt.updateBrokerConfig(
        _serverController.text.trim(),
        nextPort: mqtt.port,
      );
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message.toString())),
        );
      }
      setState(() {
        _isLoading = false;
      });
      return;
    }

    if (_isLoginMode) {
      success = await api.login(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );
    } else {
      success = await api.registerUser(
        _emailController.text.trim(),
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );
    }

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      if (success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DeviceSelectionScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              api.lastError ??
                  (_isLoginMode ? 'Login failed' : 'Registration failed'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService();

    return Scaffold(
      appBar: AppBar(title: Text(_isLoginMode ? 'Login' : 'Register')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.rocket_launch, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 32),
                
                if (!_isLoginMode) ...[
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                ],
                
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    labelText: 'Server IP / Host',
                    border: OutlineInputBorder(),
                    helperText: 'Example: 10.235.155.125 or 10.0.2.2',
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Saved API: ${api.baseUrl}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator()
                      : Text(_isLoginMode ? 'Login' : 'Register'),
                ),
                
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLoginMode = !_isLoginMode;
                    });
                  },
                  child: Text(_isLoginMode 
                    ? 'Don\'t have an account? Register' 
                    : 'Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _serverController.dispose();
    super.dispose();
  }
}
