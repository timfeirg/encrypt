part of encrypt;

/// Wraps the Fernet Algorithm.
class Fernet implements Algorithm {
  final _maxClockSkew = 60;
  final _randomGenerator = Random.secure();
  Key _signKey;
  Key _encryptionKey;
  Clock _clock;

  Fernet(Key b64key, {Clock clock}) {
    final keyString = convert.utf8.decode(b64key.bytes);
    final keyBytes = convert.base64Url.decode(keyString);
    if (keyBytes.length != 32) {
      throw StateError('Fernet key must be 32 url-safe base64-encoded bytes.');
    }
    _signKey = Key(Uint8List.fromList(keyBytes.sublist(0, 16)));
    _encryptionKey = Key(Uint8List.fromList(keyBytes.sublist(16)));
    if (clock == null) {
      _clock = Clock();
    } else {
      _clock = clock;
    }
  }

  @override
  Encrypted encrypt(Uint8List bytes, {IV iv}) {
    if (iv == null) {
      iv = _generateIV();
    }
    int currentTime = (_clock.now().millisecondsSinceEpoch / 1000).round();
    final encryptedBytes = _encryptFromParts(bytes, currentTime, iv);
    return Encrypted(encryptedBytes);
  }

  @override
  Uint8List decrypt(Encrypted encrypted, {IV iv, int ttl}) {
    final data = encrypted.bytes;
    if (data.first != 0x80) {
      throw StateError('Invalid token');
    }
    final ts = extractTimestamp(data);
    final now = (_clock.now().millisecondsSinceEpoch / 1000).round();
    if (ttl != null && ts + ttl < now) {
      throw StateError('Invalid token');
    }
    if (now + _maxClockSkew < ts) {
      throw StateError('Invalid token');
    }
    _verify_signature(data);
    if (iv != null) {
      throw StateError('IV must be infered from token');
    }
    iv = IV(Uint8List.fromList(data.sublist(9, 25)));
    final length = data.length;
    final ciphertext =
        Encrypted(Uint8List.fromList(data.sublist(25, length - 32)));
    final aes = AES(_encryptionKey, mode: AESMode.cbc);
    final decrypted = aes.decrypt(ciphertext, iv: iv);
    return decrypted;
  }

  int extractTimestamp(Uint8List data) {
    final tsBytes = data.sublist(1, 9);
    var buffer = Uint8List.fromList(tsBytes).buffer;
    var bdata = ByteData.view(buffer);
    return bdata.getUint64(0, Endian.big);
  }

  void _verify_signature(Uint8List data) {
    final length = data.length;
    final parts = data.sublist(0, length - 32);
    final _digest = data.sublist(length - 32);
    var hmac = Hmac(sha256, _signKey.bytes);
    final digest_ = hmac.convert(parts).bytes;
    if (!ListEquality().equals(_digest, digest_)) {
      throw StateError('Invalid token');
    }
  }

  IV _generateIV() {
    final bs = List.generate(16, (_) => _randomGenerator.nextInt(255));
    return IV(Uint8List.fromList(bs));
  }

  Uint8List _encryptFromParts(Uint8List bytes, int currentTime, IV iv) {
    final aes = AES(_encryptionKey, mode: AESMode.cbc);
    final cipherText = aes.encrypt(bytes, iv: iv);
    // convert epoch timestamp to binary data, in bytes
    var buffer = Uint8List(8).buffer;
    var bdata = ByteData.view(buffer);
    bdata.setUint64(0, currentTime, Endian.big);
    final currentTimeBytes = bdata.buffer.asUint8List();

    final parts = [0x80, ...currentTimeBytes, ...iv.bytes, ...cipherText.bytes];
    var hmac = Hmac(sha256, _signKey.bytes);
    var digest = hmac.convert(parts).bytes;
    final result = [...parts, ...Uint8List.fromList(digest)];
    return Uint8List.fromList(result);
  }
}
