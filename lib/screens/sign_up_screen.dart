import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace_foodchain_app/services/service_functions.dart';
import 'package:trace_foodchain_app/widgets/status_bar.dart';
import 'package:trace_foodchain_app/widgets/language_selector.dart'; // Neue Import
import '../l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/user_profile_setup_screen.dart';
import '../services/open_ral_service.dart';
import '../main.dart'; // Für appUserDoc, cloudLogService
import '../constants.dart'; // Für APP_VERSION

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _getString(String key, String lang) {
    const Map<String, Map<String, String>> strings = {
      'signIn': {
        'en': 'Sign In',
        'de': 'Anmelden',
        'es': 'Iniciar sesión',
        'fr': 'Se connecter',
      },
      'createAccount': {
        'en': 'Create Account',
        'de': 'Konto erstellen',
        'es': 'Crear cuenta',
        'fr': 'Créer un compte',
      },
      'confirmPassword': {
        'en': 'Confirm Password',
        'de': 'Passwort bestätigen',
        'es': 'Confirmar contraseña',
        'fr': 'Confirmer le mot de passe',
      },
      'passwordsDoNotMatch': {
        'en': 'Passwords do not match',
        'de': 'Passwörter stimmen nicht überein',
        'es': 'Las contraseñas no coinciden',
        'fr': 'Les mots de passe ne correspondent pas',
      },
      'passwordTooShort': {
        'en': 'Password must be at least 8 characters',
        'de': 'Passwort muss mindestens 8 Zeichen lang sein',
        'es': 'La contraseña debe tener al menos 8 caracteres',
        'fr': 'Le mot de passe doit comporter au moins 8 caractères',
      },
      'dontHaveAccount': {
        'en': "Don't have an account? Create one",
        'de': 'Noch kein Konto? Jetzt registrieren',
        'es': '¿No tiene una cuenta? Crear una',
        'fr': "Vous n'avez pas de compte ? Créez-en un",
      },
      'alreadyHaveAccount': {
        'en': 'Already have an account? Sign In',
        'de': 'Bereits ein Konto? Anmelden',
        'es': '¿Ya tiene una cuenta? Iniciar sesión',
        'fr': 'Vous avez déjà un compte ? Se connecter',
      },
      'authSuccessTitle': {
        'en': 'Signed in successfully.',
        'de': 'Erfolgreich angemeldet.',
        'es': 'Sesión iniciada con éxito.',
        'fr': 'Connecté avec succès.',
      },
      'regSuccessTitle': {
        'en': 'Account created successfully. Please check your email for verification.',
        'de': 'Konto erfolgreich erstellt. Bitte überprüfen Sie Ihre E-Mails zur Bestätigung.',
        'es': 'Cuenta creada con éxito. Por favor revise su correo para verificación.',
        'fr': 'Compte créé avec succès. Veuillez vérifier votre boîte mail.',
      },
    };
    final langKey = ['de', 'es', 'fr'].contains(lang) ? lang : 'en';
    return strings[key]?[langKey] ?? strings[key]?['en'] ?? key;
  }

  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;

    final lang = Localizations.localeOf(context).languageCode;

    if (_isSignUp) {
      if (_passwordController.text != _confirmPasswordController.text) {
        await fshowInfoDialog(context, _getString('passwordsDoNotMatch', lang));
        return;
      }
      if (_passwordController.text.length < 8) {
        await fshowInfoDialog(context, _getString('passwordTooShort', lang));
        return;
      }
    }

    setState(() => _isLoading = true);

    // Generate session ID here so it covers the full lifecycle incl. SplashScreen
    if (cloudLogService.sessionId == null) {
      cloudLogService.generateSessionId();
    }

    try {
      if (!_isSignUp) {
        // Explicit Sign-in
        await cloudLogService.info('AuthScreen: Sign-in attempt started',
            data: {'email': _emailController.text.trim()});
        UserCredential userCredential =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        await cloudLogService.info('AuthScreen: Sign-in successful',
            data: {'uid': userCredential.user!.uid});
        if (mounted) {
          await _handleSuccessfulAuth(
              userCredential.user!, _getString('authSuccessTitle', lang));
        }
      } else {
        // Explicit Sign-up
        await cloudLogService.info('AuthScreen: Sign-up attempt started',
            data: {'email': _emailController.text.trim()});
        UserCredential userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        await userCredential.user?.sendEmailVerification();
        await cloudLogService.info(
            'AuthScreen: New account created, verification email sent',
            data: {'uid': userCredential.user!.uid});
        if (mounted) {
          await _handleSuccessfulAuth(userCredential.user!,
              _getString('regSuccessTitle', lang));
        }
      }
    } on FirebaseAuthException catch (e) {
      await cloudLogService.error(
          _isSignUp
              ? 'AuthScreen: Account creation failed'
              : 'AuthScreen: Sign-in failed',
          data: {'code': e.code, 'message': e.message});
      if (mounted) {
        await _handleAuthError(e);
      }
    } catch (e) {
      await cloudLogService.error('AuthScreen: Unexpected auth error',
          data: {'error': e.toString()});
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        await fshowInfoDialog(context, "${l10n.error}: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSuccessfulAuth(User user, String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', user.uid);

    // Start cloud log session now that we know userId and are (likely) online
    await cloudLogService.startSession(user.uid, email: user.email);
    await cloudLogService.info(
        'AuthScreen: handleSuccessfulAuth – userId saved, initializing user data',
        data: {'uid': user.uid, 'email': user.email ?? ''});

    // Load the user's appUserDoc from cloud/local storage
    await cloudLogService.info('AuthScreen: Loading user profile (appUserDoc)');
    await _loadAppUserDoc(user);
    await cloudLogService.info(
        appUserDoc != null
            ? 'AuthScreen: User profile loaded successfully'
            : 'AuthScreen: User profile not found (new user or not yet synced)',
        data: {'hasProfile': appUserDoc != null});

    // Always check if user profile is complete, regardless of new or existing user
    // This ensures we always have the userRole
    await cloudLogService.info('AuthScreen: Checking profile completeness');
    await _checkAndNavigateToProfileSetup(user);
  }

  Future<void> _loadAppUserDoc(User user) async {
    try {
      // Try to get user object from OpenRAL service
      final userObject = await OpenRALService.getUserObjectByUID(user.uid);
      if (userObject != null) {
        // Set the global appUserDoc variable from main.dart
        appUserDoc = userObject;
      }
    } catch (e) {
      debugPrint('Error loading appUserDoc: $e');
    }
  }

  Future<void> _checkAndNavigateToProfileSetup(User user) async {
    try {
      // Check if user profile is already complete.
      // This can hit the network (Firestore), so the screen may well be gone by
      // the time it returns - another navigation may already have taken over.
      final userProfile = await OpenRALService.getUserProfile();
      if (!mounted) return;

      final bool hasFirstName = userProfile.containsKey('firstName') &&
          userProfile['firstName']!.isNotEmpty;
      final bool hasLastName = userProfile.containsKey('lastName') &&
          userProfile['lastName']!.isNotEmpty;
      final bool hasCountry = userProfile.containsKey('country') &&
          userProfile['country']!.isNotEmpty;

      // Required fields: firstName, lastName, and country
      // userRole is optional and will default to "Trader" if not set
      if (!hasFirstName || !hasLastName || !hasCountry) {
        // Navigate to profile setup screen
        _openProfileSetup();
      } else {
        // Profile is complete, navigate based on user role
        _navigateBasedOnRole(userProfile);
      }
    } catch (e) {
      // Do not swallow this silently: without the log, a failing profile lookup
      // is indistinguishable from "profile is incomplete".
      await cloudLogService.error('AuthScreen: profile check failed',
          data: {'error': e.toString()});
      // On error, navigate to profile setup to be safe
      _openProfileSetup();
    }
  }

  void _openProfileSetup() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const UserProfileSetupScreen(),
      ),
    );
  }

  void _navigateBasedOnRole(Map<String, String> userProfile) {
    if (!mounted) return;
    // Nach Login IMMER zum SplashScreen navigieren
    // Der SplashScreen führt die vollständige Initialisierung durch
    // und navigiert dann basierend auf der Rolle zum richtigen Screen
    Navigator.of(context).pushReplacementNamed('/');
  }

  Future<void> _handleAuthError(FirebaseAuthException e) async {
    final l10n = AppLocalizations.of(context)!;
    String errorMessage;
    switch (e.code) {
      case 'weak-password':
        errorMessage = l10n.weakPasswordError;
        break;
      case 'email-already-in-use':
        errorMessage = l10n.emailAlreadyInUseError;
        break;
      case 'invalid-email':
        errorMessage = l10n.invalidEmailError;
        break;
      case 'user-disabled':
        errorMessage = l10n.userDisabledError;
        break;
      case 'wrong-password':
      case 'invalid-credential':
      case 'user-not-found':
        errorMessage = l10n.wrongPasswordError;
        break;
      default:
        errorMessage = e.message ?? l10n.undefinedError;
    }
    await fshowInfoDialog(context, "${l10n.error}: $errorMessage");
  }

  String _getHelpUrl(String languageCode) {
    switch (languageCode) {
      case 'de':
        return 'https://docs.google.com/document/d/1wURF_uGIW3eKHh1qEn380_JE5tOdOyZRfFRQuL46Hn0';
      case 'es':
        return 'https://docs.google.com/document/d/1IVqaR_mJkQKbVobJfYM_EUxYCpd5B5qel0mY2U_KPVg';
      case 'fr':
        return 'https://docs.google.com/document/d/19Z0dMR6CqHqaT2nU9qM4uzHftNFlIeZpd2AlyuHngP4';
      default:
        return "https://docs.google.com/document/d/1JcNxTNEs6nkTDotVzFw-AFU0arB6T8aI1BfzKAuDF0A";
    }
  }

  Future<void> _launchHelp() async {
    final locale = Localizations.localeOf(context);
    final Uri url = Uri.parse(_getHelpUrl(locale.languageCode));
    if (!await launchUrl(url)) {
      await fshowInfoDialog(
          context, AppLocalizations.of(context)!.errorOpeningUrl);
    }
  }

  // Neue Methode: Passwort zurücksetzen
  Future<void> _resetPassword() async {
    final email = _emailController.text;
    if (email.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      await fshowInfoDialog(context, l10n.pleaseEnterEmail);
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      final l10n = AppLocalizations.of(context)!;
      await fshowInfoDialog(context, l10n.resetPasswordEmailSent);
    } on FirebaseAuthException catch (e) {
      await fshowInfoDialog(context, e.message ?? "Error");
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF35DB00),
        onPressed: _launchHelp,
        tooltip: l10n.helpButtonTooltip,
        child: const Icon(Icons.menu_book),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/background.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.white.withOpacity(0.7),
                  BlendMode.dstATop,
                ),
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  const Positioned(
                    top: 16,
                    left: 16,
                    child: LanguageSelector(),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Text(
                      APP_VERSION,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Card(
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.welcomeToApp,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.bold,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.signInMessage,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.black54,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  // Auth Mode Switcher (Sign In vs Create Account)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(25),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              if (_isSignUp) {
                                                setState(() {
                                                  _isSignUp = false;
                                                  _formKey.currentState?.reset();
                                                });
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              decoration: BoxDecoration(
                                                color: !_isSignUp
                                                    ? Theme.of(context).primaryColor
                                                    : Colors.transparent,
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                _getString('signIn', Localizations.localeOf(context).languageCode),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: !_isSignUp ? Colors.white : Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              if (!_isSignUp) {
                                                setState(() {
                                                  _isSignUp = true;
                                                  _formKey.currentState?.reset();
                                                });
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              decoration: BoxDecoration(
                                                color: _isSignUp
                                                    ? Theme.of(context).primaryColor
                                                    : Colors.transparent,
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                _getString('createAccount', Localizations.localeOf(context).languageCode),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: _isSignUp ? Colors.white : Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Form(
                                    key: _formKey,
                                    child: Column(
                                      children: <Widget>[
                                        TextFormField(
                                          style: const TextStyle(
                                              color: Colors.black),
                                          controller: _emailController,
                                          keyboardType: TextInputType.emailAddress,
                                          decoration: InputDecoration(
                                            labelText: l10n.email,
                                            prefixIcon: const Icon(Icons.email),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return l10n.pleaseEnterEmail;
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          onFieldSubmitted: (value) {
                                            if (!_isSignUp) _authenticate();
                                          },
                                          style: const TextStyle(
                                              color: Colors.black),
                                          controller: _passwordController,
                                          decoration: InputDecoration(
                                            labelText: l10n.password,
                                            prefixIcon: const Icon(Icons.lock),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          obscureText: true,
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return l10n.pleaseEnterPassword;
                                            }
                                            return null;
                                          },
                                        ),
                                        if (_isSignUp) ...[
                                          const SizedBox(height: 16),
                                          TextFormField(
                                            onFieldSubmitted: (value) {
                                              _authenticate();
                                            },
                                            style: const TextStyle(
                                                color: Colors.black),
                                            controller: _confirmPasswordController,
                                            decoration: InputDecoration(
                                              labelText: _getString('confirmPassword', Localizations.localeOf(context).languageCode),
                                              prefixIcon: const Icon(Icons.lock_outline),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            obscureText: true,
                                            validator: (value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return l10n.pleaseEnterPassword;
                                              }
                                              if (value != _passwordController.text) {
                                                return _getString('passwordsDoNotMatch', Localizations.localeOf(context).languageCode);
                                              }
                                              return null;
                                            },
                                          ),
                                        ],
                                        if (!_isSignUp) ...[
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton(
                                              onPressed: _resetPassword,
                                              child: Text(
                                                l10n.forgotPasswordQuestion,
                                                style: const TextStyle(
                                                  color: Color(0xFF35DB00),
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 24),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: _isLoading ? null : _authenticate,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Theme.of(context).primaryColor,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 15),
                                              textStyle:
                                                  const TextStyle(fontSize: 18),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                            ),
                                            child: _isLoading
                                                ? const SizedBox(
                                                    height: 24,
                                                    width: 24,
                                                    child: CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                                  )
                                                : Text(_getString(_isSignUp ? 'createAccount' : 'signIn', Localizations.localeOf(context).languageCode)),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _isSignUp = !_isSignUp;
                                              _formKey.currentState?.reset();
                                            });
                                          },
                                          child: Text(
                                            _getString(_isSignUp ? 'alreadyHaveAccount' : 'dontHaveAccount', Localizations.localeOf(context).languageCode),
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            bottom: 16,
            left: 16,
            child: StatusBar(isSmallScreen: false),
          ),
        ],
      ),
    );
  }
}
