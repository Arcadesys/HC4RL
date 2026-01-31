import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/camera_service.dart';
import '../../utils/camera_image_to_file.dart';
import 'face_dataset.dart';
import 'face_verification_service.dart';

class FaceNamesScreen extends StatefulWidget {
  const FaceNamesScreen({super.key});

  @override
  State<FaceNamesScreen> createState() => _FaceNamesScreenState();
}

class _FaceNamesScreenState extends State<FaceNamesScreen> {
  CameraController? _controller;
  String? _error;
  final FaceDataset _dataset = FaceDataset();
  String? _matchedName;
  bool _processing = false;
  DateTime? _lastVerifyTime;

  @override
  void initState() {
    super.initState();
    _dataset.load().then((_) => setState(() {}));
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final controller = await CameraService.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _error = null;
      });
      if (await CameraService.supportsImageStreaming(controller)) {
        await CameraService.startImageStream(controller, _onImage);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onImage(CameraImage image) {
    if (_processing) return;
    final now = DateTime.now();
    if (_lastVerifyTime != null &&
        now.difference(_lastVerifyTime!).inMilliseconds < 500) {
      return;
    }
    _processing = true;
    _lastVerifyTime = now;
    saveCameraImageToTempJpeg(image).then((path) async {
      if (path == null || !mounted) {
        if (mounted) setState(() => _processing = false);
        return;
      }
      try {
        final id = await FaceVerificationService.verifyFromPath(
          imagePath: path,
          threshold: 0.70,
        );
        try {
          File(path).deleteSync();
        } catch (_) {}
        if (!mounted) {
          setState(() => _processing = false);
          return;
        }
        final name = id != null ? _dataset.nameForId(id) : null;
        setState(() {
          _matchedName = name;
          _processing = false;
        });
      } catch (_) {
        if (mounted) setState(() => _processing = false);
      }
    }).catchError((_) {
      if (mounted) setState(() => _processing = false);
    });
  }

  @override
  void dispose() {
    if (_controller != null) CameraService.dispose(_controller!);
    super.dispose();
  }

  Future<void> _openAddPerson() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddPersonScreen(dataset: _dataset),
      ),
    );
    if (result == true && mounted) {
      await _dataset.load();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face & Names')),
        body: Center(child: Text(_error!)),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face & Names')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face & Names'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _openAddPerson,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: CameraPreview(_controller!),
          ),
          if (_matchedName != null)
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.of(context).padding.top + 8,
              child: Material(
                color: Colors.black54,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Text(
                    _matchedName!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AddPersonScreen extends StatefulWidget {
  const AddPersonScreen({super.key, required this.dataset});
  final FaceDataset dataset;

  @override
  State<AddPersonScreen> createState() => _AddPersonScreenState();
}

class _AddPersonScreenState extends State<AddPersonScreen> {
  final TextEditingController _nameController = TextEditingController();
  String? _capturedPath;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _captureAndRegister() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (_capturedPath == null) {
      setState(() => _error = 'Capture a photo first');
      return;
    }
    setState(() => _error = null);
    try {
      final id = widget.dataset.add(name);
      await widget.dataset.save();
      await FaceVerificationService.registerFromPath(
        personId: id,
        imagePath: _capturedPath!,
        imageId: 'main',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add person')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Enter their name',
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            const Text(
              'Take a clear photo of the person\'s face, then enter their name and tap Save.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final path = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const _CapturePhotoScreen(),
                  ),
                );
                if (path != null && mounted)
                  setState(() => _capturedPath = path);
              },
              child: Text(_capturedPath == null
                  ? 'Take photo'
                  : 'Photo captured (tap to retake)'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _captureAndRegister,
              child: const Text('Save person'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapturePhotoScreen extends StatefulWidget {
  const _CapturePhotoScreen();

  @override
  State<_CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends State<_CapturePhotoScreen> {
  CameraController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final controller = await CameraService.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    if (_controller != null) CameraService.dispose(_controller!);
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final XFile file = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Take photo')),
        body: Center(child: Text(_error!)),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Take photo')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Take photo')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: CameraPreview(_controller!)),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton(
                  onPressed: _capture,
                  child: const Text('Capture'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
