// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unused_element

part of 'app_database.dart';

// ignore_for_file: type=lint
class $_TasksTable extends _Tasks with TableInfo<$_TasksTable, _Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $_TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _schemaVersionMeta =
      const VerificationMeta('schemaVersion');
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
      'schema_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _payloadNonceMeta =
      const VerificationMeta('payloadNonce');
  @override
  late final GeneratedColumn<Uint8List> payloadNonce =
      GeneratedColumn<Uint8List>('payload_nonce', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _payloadCiphertextMeta =
      const VerificationMeta('payloadCiphertext');
  @override
  late final GeneratedColumn<Uint8List> payloadCiphertext =
      GeneratedColumn<Uint8List>('payload_ciphertext', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        accountId,
        recordId,
        schemaVersion,
        payloadNonce,
        payloadCiphertext,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(Insertable<_Task> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
          _schemaVersionMeta,
          schemaVersion.isAcceptableOrUnknown(
              data['schema_version']!, _schemaVersionMeta));
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('payload_nonce')) {
      context.handle(
          _payloadNonceMeta,
          payloadNonce.isAcceptableOrUnknown(
              data['payload_nonce']!, _payloadNonceMeta));
    } else if (isInserting) {
      context.missing(_payloadNonceMeta);
    }
    if (data.containsKey('payload_ciphertext')) {
      context.handle(
          _payloadCiphertextMeta,
          payloadCiphertext.isAcceptableOrUnknown(
              data['payload_ciphertext']!, _payloadCiphertextMeta));
    } else if (isInserting) {
      context.missing(_payloadCiphertextMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, recordId};
  @override
  _Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return _Task(
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      schemaVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}schema_version'])!,
      payloadNonce: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}payload_nonce'])!,
      payloadCiphertext: attachedDatabase.typeMapping.read(
          DriftSqlType.blob, data['${effectivePrefix}payload_ciphertext'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $_TasksTable createAlias(String alias) {
    return $_TasksTable(attachedDatabase, alias);
  }
}

class _Task extends DataClass implements Insertable<_Task> {
  final String accountId;
  final String recordId;
  final int schemaVersion;
  final Uint8List payloadNonce;
  final Uint8List payloadCiphertext;
  final DateTime updatedAt;
  const _Task(
      {required this.accountId,
      required this.recordId,
      required this.schemaVersion,
      required this.payloadNonce,
      required this.payloadCiphertext,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['record_id'] = Variable<String>(recordId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['payload_nonce'] = Variable<Uint8List>(payloadNonce);
    map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  _TasksCompanion toCompanion(bool nullToAbsent) {
    return _TasksCompanion(
      accountId: Value(accountId),
      recordId: Value(recordId),
      schemaVersion: Value(schemaVersion),
      payloadNonce: Value(payloadNonce),
      payloadCiphertext: Value(payloadCiphertext),
      updatedAt: Value(updatedAt),
    );
  }

  factory _Task.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return _Task(
      accountId: serializer.fromJson<String>(json['accountId']),
      recordId: serializer.fromJson<String>(json['recordId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      payloadNonce: serializer.fromJson<Uint8List>(json['payloadNonce']),
      payloadCiphertext:
          serializer.fromJson<Uint8List>(json['payloadCiphertext']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'recordId': serializer.toJson<String>(recordId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'payloadNonce': serializer.toJson<Uint8List>(payloadNonce),
      'payloadCiphertext': serializer.toJson<Uint8List>(payloadCiphertext),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  _Task copyWith(
          {String? accountId,
          String? recordId,
          int? schemaVersion,
          Uint8List? payloadNonce,
          Uint8List? payloadCiphertext,
          DateTime? updatedAt}) =>
      _Task(
        accountId: accountId ?? this.accountId,
        recordId: recordId ?? this.recordId,
        schemaVersion: schemaVersion ?? this.schemaVersion,
        payloadNonce: payloadNonce ?? this.payloadNonce,
        payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  _Task copyWithCompanion(_TasksCompanion data) {
    return _Task(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      payloadNonce: data.payloadNonce.present
          ? data.payloadNonce.value
          : this.payloadNonce,
      payloadCiphertext: data.payloadCiphertext.present
          ? data.payloadCiphertext.value
          : this.payloadCiphertext,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('_Task(')
          ..write('accountId: $accountId, ')
          ..write('recordId: $recordId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      accountId,
      recordId,
      schemaVersion,
      $driftBlobEquality.hash(payloadNonce),
      $driftBlobEquality.hash(payloadCiphertext),
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _Task &&
          other.accountId == this.accountId &&
          other.recordId == this.recordId &&
          other.schemaVersion == this.schemaVersion &&
          $driftBlobEquality.equals(other.payloadNonce, this.payloadNonce) &&
          $driftBlobEquality.equals(
              other.payloadCiphertext, this.payloadCiphertext) &&
          other.updatedAt == this.updatedAt);
}

class _TasksCompanion extends UpdateCompanion<_Task> {
  final Value<String> accountId;
  final Value<String> recordId;
  final Value<int> schemaVersion;
  final Value<Uint8List> payloadNonce;
  final Value<Uint8List> payloadCiphertext;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const _TasksCompanion({
    this.accountId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.payloadNonce = const Value.absent(),
    this.payloadCiphertext = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  _TasksCompanion.insert({
    required String accountId,
    required String recordId,
    required int schemaVersion,
    required Uint8List payloadNonce,
    required Uint8List payloadCiphertext,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : accountId = Value(accountId),
        recordId = Value(recordId),
        schemaVersion = Value(schemaVersion),
        payloadNonce = Value(payloadNonce),
        payloadCiphertext = Value(payloadCiphertext),
        updatedAt = Value(updatedAt);
  static Insertable<_Task> custom({
    Expression<String>? accountId,
    Expression<String>? recordId,
    Expression<int>? schemaVersion,
    Expression<Uint8List>? payloadNonce,
    Expression<Uint8List>? payloadCiphertext,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (recordId != null) 'record_id': recordId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (payloadNonce != null) 'payload_nonce': payloadNonce,
      if (payloadCiphertext != null) 'payload_ciphertext': payloadCiphertext,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  _TasksCompanion copyWith(
      {Value<String>? accountId,
      Value<String>? recordId,
      Value<int>? schemaVersion,
      Value<Uint8List>? payloadNonce,
      Value<Uint8List>? payloadCiphertext,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return _TasksCompanion(
      accountId: accountId ?? this.accountId,
      recordId: recordId ?? this.recordId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      payloadNonce: payloadNonce ?? this.payloadNonce,
      payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (payloadNonce.present) {
      map['payload_nonce'] = Variable<Uint8List>(payloadNonce.value);
    }
    if (payloadCiphertext.present) {
      map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('_TasksCompanion(')
          ..write('accountId: $accountId, ')
          ..write('recordId: $recordId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $_ScheduleBlocksTable extends _ScheduleBlocks
    with TableInfo<$_ScheduleBlocksTable, _ScheduleBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $_ScheduleBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _schemaVersionMeta =
      const VerificationMeta('schemaVersion');
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
      'schema_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _payloadNonceMeta =
      const VerificationMeta('payloadNonce');
  @override
  late final GeneratedColumn<Uint8List> payloadNonce =
      GeneratedColumn<Uint8List>('payload_nonce', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _payloadCiphertextMeta =
      const VerificationMeta('payloadCiphertext');
  @override
  late final GeneratedColumn<Uint8List> payloadCiphertext =
      GeneratedColumn<Uint8List>('payload_ciphertext', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        accountId,
        recordId,
        schemaVersion,
        payloadNonce,
        payloadCiphertext,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_blocks';
  @override
  VerificationContext validateIntegrity(Insertable<_ScheduleBlock> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
          _schemaVersionMeta,
          schemaVersion.isAcceptableOrUnknown(
              data['schema_version']!, _schemaVersionMeta));
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('payload_nonce')) {
      context.handle(
          _payloadNonceMeta,
          payloadNonce.isAcceptableOrUnknown(
              data['payload_nonce']!, _payloadNonceMeta));
    } else if (isInserting) {
      context.missing(_payloadNonceMeta);
    }
    if (data.containsKey('payload_ciphertext')) {
      context.handle(
          _payloadCiphertextMeta,
          payloadCiphertext.isAcceptableOrUnknown(
              data['payload_ciphertext']!, _payloadCiphertextMeta));
    } else if (isInserting) {
      context.missing(_payloadCiphertextMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, recordId};
  @override
  _ScheduleBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return _ScheduleBlock(
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      schemaVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}schema_version'])!,
      payloadNonce: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}payload_nonce'])!,
      payloadCiphertext: attachedDatabase.typeMapping.read(
          DriftSqlType.blob, data['${effectivePrefix}payload_ciphertext'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $_ScheduleBlocksTable createAlias(String alias) {
    return $_ScheduleBlocksTable(attachedDatabase, alias);
  }
}

class _ScheduleBlock extends DataClass implements Insertable<_ScheduleBlock> {
  final String accountId;
  final String recordId;
  final int schemaVersion;
  final Uint8List payloadNonce;
  final Uint8List payloadCiphertext;
  final DateTime updatedAt;
  const _ScheduleBlock(
      {required this.accountId,
      required this.recordId,
      required this.schemaVersion,
      required this.payloadNonce,
      required this.payloadCiphertext,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['record_id'] = Variable<String>(recordId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['payload_nonce'] = Variable<Uint8List>(payloadNonce);
    map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  _ScheduleBlocksCompanion toCompanion(bool nullToAbsent) {
    return _ScheduleBlocksCompanion(
      accountId: Value(accountId),
      recordId: Value(recordId),
      schemaVersion: Value(schemaVersion),
      payloadNonce: Value(payloadNonce),
      payloadCiphertext: Value(payloadCiphertext),
      updatedAt: Value(updatedAt),
    );
  }

  factory _ScheduleBlock.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return _ScheduleBlock(
      accountId: serializer.fromJson<String>(json['accountId']),
      recordId: serializer.fromJson<String>(json['recordId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      payloadNonce: serializer.fromJson<Uint8List>(json['payloadNonce']),
      payloadCiphertext:
          serializer.fromJson<Uint8List>(json['payloadCiphertext']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'recordId': serializer.toJson<String>(recordId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'payloadNonce': serializer.toJson<Uint8List>(payloadNonce),
      'payloadCiphertext': serializer.toJson<Uint8List>(payloadCiphertext),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  _ScheduleBlock copyWith(
          {String? accountId,
          String? recordId,
          int? schemaVersion,
          Uint8List? payloadNonce,
          Uint8List? payloadCiphertext,
          DateTime? updatedAt}) =>
      _ScheduleBlock(
        accountId: accountId ?? this.accountId,
        recordId: recordId ?? this.recordId,
        schemaVersion: schemaVersion ?? this.schemaVersion,
        payloadNonce: payloadNonce ?? this.payloadNonce,
        payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  _ScheduleBlock copyWithCompanion(_ScheduleBlocksCompanion data) {
    return _ScheduleBlock(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      payloadNonce: data.payloadNonce.present
          ? data.payloadNonce.value
          : this.payloadNonce,
      payloadCiphertext: data.payloadCiphertext.present
          ? data.payloadCiphertext.value
          : this.payloadCiphertext,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('_ScheduleBlock(')
          ..write('accountId: $accountId, ')
          ..write('recordId: $recordId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      accountId,
      recordId,
      schemaVersion,
      $driftBlobEquality.hash(payloadNonce),
      $driftBlobEquality.hash(payloadCiphertext),
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _ScheduleBlock &&
          other.accountId == this.accountId &&
          other.recordId == this.recordId &&
          other.schemaVersion == this.schemaVersion &&
          $driftBlobEquality.equals(other.payloadNonce, this.payloadNonce) &&
          $driftBlobEquality.equals(
              other.payloadCiphertext, this.payloadCiphertext) &&
          other.updatedAt == this.updatedAt);
}

class _ScheduleBlocksCompanion extends UpdateCompanion<_ScheduleBlock> {
  final Value<String> accountId;
  final Value<String> recordId;
  final Value<int> schemaVersion;
  final Value<Uint8List> payloadNonce;
  final Value<Uint8List> payloadCiphertext;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const _ScheduleBlocksCompanion({
    this.accountId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.payloadNonce = const Value.absent(),
    this.payloadCiphertext = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  _ScheduleBlocksCompanion.insert({
    required String accountId,
    required String recordId,
    required int schemaVersion,
    required Uint8List payloadNonce,
    required Uint8List payloadCiphertext,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : accountId = Value(accountId),
        recordId = Value(recordId),
        schemaVersion = Value(schemaVersion),
        payloadNonce = Value(payloadNonce),
        payloadCiphertext = Value(payloadCiphertext),
        updatedAt = Value(updatedAt);
  static Insertable<_ScheduleBlock> custom({
    Expression<String>? accountId,
    Expression<String>? recordId,
    Expression<int>? schemaVersion,
    Expression<Uint8List>? payloadNonce,
    Expression<Uint8List>? payloadCiphertext,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (recordId != null) 'record_id': recordId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (payloadNonce != null) 'payload_nonce': payloadNonce,
      if (payloadCiphertext != null) 'payload_ciphertext': payloadCiphertext,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  _ScheduleBlocksCompanion copyWith(
      {Value<String>? accountId,
      Value<String>? recordId,
      Value<int>? schemaVersion,
      Value<Uint8List>? payloadNonce,
      Value<Uint8List>? payloadCiphertext,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return _ScheduleBlocksCompanion(
      accountId: accountId ?? this.accountId,
      recordId: recordId ?? this.recordId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      payloadNonce: payloadNonce ?? this.payloadNonce,
      payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (payloadNonce.present) {
      map['payload_nonce'] = Variable<Uint8List>(payloadNonce.value);
    }
    if (payloadCiphertext.present) {
      map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('_ScheduleBlocksCompanion(')
          ..write('accountId: $accountId, ')
          ..write('recordId: $recordId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $_FocusSessionsTable extends _FocusSessions
    with TableInfo<$_FocusSessionsTable, _FocusSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $_FocusSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _schemaVersionMeta =
      const VerificationMeta('schemaVersion');
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
      'schema_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _payloadNonceMeta =
      const VerificationMeta('payloadNonce');
  @override
  late final GeneratedColumn<Uint8List> payloadNonce =
      GeneratedColumn<Uint8List>('payload_nonce', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _payloadCiphertextMeta =
      const VerificationMeta('payloadCiphertext');
  @override
  late final GeneratedColumn<Uint8List> payloadCiphertext =
      GeneratedColumn<Uint8List>('payload_ciphertext', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        accountId,
        recordId,
        schemaVersion,
        payloadNonce,
        payloadCiphertext,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<_FocusSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
          _schemaVersionMeta,
          schemaVersion.isAcceptableOrUnknown(
              data['schema_version']!, _schemaVersionMeta));
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('payload_nonce')) {
      context.handle(
          _payloadNonceMeta,
          payloadNonce.isAcceptableOrUnknown(
              data['payload_nonce']!, _payloadNonceMeta));
    } else if (isInserting) {
      context.missing(_payloadNonceMeta);
    }
    if (data.containsKey('payload_ciphertext')) {
      context.handle(
          _payloadCiphertextMeta,
          payloadCiphertext.isAcceptableOrUnknown(
              data['payload_ciphertext']!, _payloadCiphertextMeta));
    } else if (isInserting) {
      context.missing(_payloadCiphertextMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, recordId};
  @override
  _FocusSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return _FocusSession(
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      schemaVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}schema_version'])!,
      payloadNonce: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}payload_nonce'])!,
      payloadCiphertext: attachedDatabase.typeMapping.read(
          DriftSqlType.blob, data['${effectivePrefix}payload_ciphertext'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $_FocusSessionsTable createAlias(String alias) {
    return $_FocusSessionsTable(attachedDatabase, alias);
  }
}

class _FocusSession extends DataClass implements Insertable<_FocusSession> {
  final String accountId;
  final String recordId;
  final int schemaVersion;
  final Uint8List payloadNonce;
  final Uint8List payloadCiphertext;
  final DateTime updatedAt;
  const _FocusSession(
      {required this.accountId,
      required this.recordId,
      required this.schemaVersion,
      required this.payloadNonce,
      required this.payloadCiphertext,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['record_id'] = Variable<String>(recordId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['payload_nonce'] = Variable<Uint8List>(payloadNonce);
    map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  _FocusSessionsCompanion toCompanion(bool nullToAbsent) {
    return _FocusSessionsCompanion(
      accountId: Value(accountId),
      recordId: Value(recordId),
      schemaVersion: Value(schemaVersion),
      payloadNonce: Value(payloadNonce),
      payloadCiphertext: Value(payloadCiphertext),
      updatedAt: Value(updatedAt),
    );
  }

  factory _FocusSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return _FocusSession(
      accountId: serializer.fromJson<String>(json['accountId']),
      recordId: serializer.fromJson<String>(json['recordId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      payloadNonce: serializer.fromJson<Uint8List>(json['payloadNonce']),
      payloadCiphertext:
          serializer.fromJson<Uint8List>(json['payloadCiphertext']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'recordId': serializer.toJson<String>(recordId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'payloadNonce': serializer.toJson<Uint8List>(payloadNonce),
      'payloadCiphertext': serializer.toJson<Uint8List>(payloadCiphertext),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  _FocusSession copyWith(
          {String? accountId,
          String? recordId,
          int? schemaVersion,
          Uint8List? payloadNonce,
          Uint8List? payloadCiphertext,
          DateTime? updatedAt}) =>
      _FocusSession(
        accountId: accountId ?? this.accountId,
        recordId: recordId ?? this.recordId,
        schemaVersion: schemaVersion ?? this.schemaVersion,
        payloadNonce: payloadNonce ?? this.payloadNonce,
        payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  _FocusSession copyWithCompanion(_FocusSessionsCompanion data) {
    return _FocusSession(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      payloadNonce: data.payloadNonce.present
          ? data.payloadNonce.value
          : this.payloadNonce,
      payloadCiphertext: data.payloadCiphertext.present
          ? data.payloadCiphertext.value
          : this.payloadCiphertext,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('_FocusSession(')
          ..write('accountId: $accountId, ')
          ..write('recordId: $recordId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      accountId,
      recordId,
      schemaVersion,
      $driftBlobEquality.hash(payloadNonce),
      $driftBlobEquality.hash(payloadCiphertext),
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _FocusSession &&
          other.accountId == this.accountId &&
          other.recordId == this.recordId &&
          other.schemaVersion == this.schemaVersion &&
          $driftBlobEquality.equals(other.payloadNonce, this.payloadNonce) &&
          $driftBlobEquality.equals(
              other.payloadCiphertext, this.payloadCiphertext) &&
          other.updatedAt == this.updatedAt);
}

class _FocusSessionsCompanion extends UpdateCompanion<_FocusSession> {
  final Value<String> accountId;
  final Value<String> recordId;
  final Value<int> schemaVersion;
  final Value<Uint8List> payloadNonce;
  final Value<Uint8List> payloadCiphertext;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const _FocusSessionsCompanion({
    this.accountId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.payloadNonce = const Value.absent(),
    this.payloadCiphertext = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  _FocusSessionsCompanion.insert({
    required String accountId,
    required String recordId,
    required int schemaVersion,
    required Uint8List payloadNonce,
    required Uint8List payloadCiphertext,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : accountId = Value(accountId),
        recordId = Value(recordId),
        schemaVersion = Value(schemaVersion),
        payloadNonce = Value(payloadNonce),
        payloadCiphertext = Value(payloadCiphertext),
        updatedAt = Value(updatedAt);
  static Insertable<_FocusSession> custom({
    Expression<String>? accountId,
    Expression<String>? recordId,
    Expression<int>? schemaVersion,
    Expression<Uint8List>? payloadNonce,
    Expression<Uint8List>? payloadCiphertext,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (recordId != null) 'record_id': recordId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (payloadNonce != null) 'payload_nonce': payloadNonce,
      if (payloadCiphertext != null) 'payload_ciphertext': payloadCiphertext,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  _FocusSessionsCompanion copyWith(
      {Value<String>? accountId,
      Value<String>? recordId,
      Value<int>? schemaVersion,
      Value<Uint8List>? payloadNonce,
      Value<Uint8List>? payloadCiphertext,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return _FocusSessionsCompanion(
      accountId: accountId ?? this.accountId,
      recordId: recordId ?? this.recordId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      payloadNonce: payloadNonce ?? this.payloadNonce,
      payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (payloadNonce.present) {
      map['payload_nonce'] = Variable<Uint8List>(payloadNonce.value);
    }
    if (payloadCiphertext.present) {
      map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('_FocusSessionsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('recordId: $recordId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $_CheckInsTable extends _CheckIns
    with TableInfo<$_CheckInsTable, _CheckIn> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $_CheckInsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _schemaVersionMeta =
      const VerificationMeta('schemaVersion');
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
      'schema_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _payloadNonceMeta =
      const VerificationMeta('payloadNonce');
  @override
  late final GeneratedColumn<Uint8List> payloadNonce =
      GeneratedColumn<Uint8List>('payload_nonce', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _payloadCiphertextMeta =
      const VerificationMeta('payloadCiphertext');
  @override
  late final GeneratedColumn<Uint8List> payloadCiphertext =
      GeneratedColumn<Uint8List>('payload_ciphertext', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        accountId,
        recordId,
        schemaVersion,
        payloadNonce,
        payloadCiphertext,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'check_ins';
  @override
  VerificationContext validateIntegrity(Insertable<_CheckIn> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
          _schemaVersionMeta,
          schemaVersion.isAcceptableOrUnknown(
              data['schema_version']!, _schemaVersionMeta));
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('payload_nonce')) {
      context.handle(
          _payloadNonceMeta,
          payloadNonce.isAcceptableOrUnknown(
              data['payload_nonce']!, _payloadNonceMeta));
    } else if (isInserting) {
      context.missing(_payloadNonceMeta);
    }
    if (data.containsKey('payload_ciphertext')) {
      context.handle(
          _payloadCiphertextMeta,
          payloadCiphertext.isAcceptableOrUnknown(
              data['payload_ciphertext']!, _payloadCiphertextMeta));
    } else if (isInserting) {
      context.missing(_payloadCiphertextMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, recordId};
  @override
  _CheckIn map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return _CheckIn(
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      schemaVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}schema_version'])!,
      payloadNonce: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}payload_nonce'])!,
      payloadCiphertext: attachedDatabase.typeMapping.read(
          DriftSqlType.blob, data['${effectivePrefix}payload_ciphertext'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $_CheckInsTable createAlias(String alias) {
    return $_CheckInsTable(attachedDatabase, alias);
  }
}

class _CheckIn extends DataClass implements Insertable<_CheckIn> {
  final String accountId;
  final String recordId;
  final int schemaVersion;
  final Uint8List payloadNonce;
  final Uint8List payloadCiphertext;
  final DateTime updatedAt;
  const _CheckIn(
      {required this.accountId,
      required this.recordId,
      required this.schemaVersion,
      required this.payloadNonce,
      required this.payloadCiphertext,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['record_id'] = Variable<String>(recordId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['payload_nonce'] = Variable<Uint8List>(payloadNonce);
    map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  _CheckInsCompanion toCompanion(bool nullToAbsent) {
    return _CheckInsCompanion(
      accountId: Value(accountId),
      recordId: Value(recordId),
      schemaVersion: Value(schemaVersion),
      payloadNonce: Value(payloadNonce),
      payloadCiphertext: Value(payloadCiphertext),
      updatedAt: Value(updatedAt),
    );
  }

  factory _CheckIn.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return _CheckIn(
      accountId: serializer.fromJson<String>(json['accountId']),
      recordId: serializer.fromJson<String>(json['recordId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      payloadNonce: serializer.fromJson<Uint8List>(json['payloadNonce']),
      payloadCiphertext:
          serializer.fromJson<Uint8List>(json['payloadCiphertext']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'recordId': serializer.toJson<String>(recordId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'payloadNonce': serializer.toJson<Uint8List>(payloadNonce),
      'payloadCiphertext': serializer.toJson<Uint8List>(payloadCiphertext),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  _CheckIn copyWith(
          {String? accountId,
          String? recordId,
          int? schemaVersion,
          Uint8List? payloadNonce,
          Uint8List? payloadCiphertext,
          DateTime? updatedAt}) =>
      _CheckIn(
        accountId: accountId ?? this.accountId,
        recordId: recordId ?? this.recordId,
        schemaVersion: schemaVersion ?? this.schemaVersion,
        payloadNonce: payloadNonce ?? this.payloadNonce,
        payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  _CheckIn copyWithCompanion(_CheckInsCompanion data) {
    return _CheckIn(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      payloadNonce: data.payloadNonce.present
          ? data.payloadNonce.value
          : this.payloadNonce,
      payloadCiphertext: data.payloadCiphertext.present
          ? data.payloadCiphertext.value
          : this.payloadCiphertext,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('_CheckIn(')
          ..write('accountId: $accountId, ')
          ..write('recordId: $recordId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      accountId,
      recordId,
      schemaVersion,
      $driftBlobEquality.hash(payloadNonce),
      $driftBlobEquality.hash(payloadCiphertext),
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _CheckIn &&
          other.accountId == this.accountId &&
          other.recordId == this.recordId &&
          other.schemaVersion == this.schemaVersion &&
          $driftBlobEquality.equals(other.payloadNonce, this.payloadNonce) &&
          $driftBlobEquality.equals(
              other.payloadCiphertext, this.payloadCiphertext) &&
          other.updatedAt == this.updatedAt);
}

class _CheckInsCompanion extends UpdateCompanion<_CheckIn> {
  final Value<String> accountId;
  final Value<String> recordId;
  final Value<int> schemaVersion;
  final Value<Uint8List> payloadNonce;
  final Value<Uint8List> payloadCiphertext;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const _CheckInsCompanion({
    this.accountId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.payloadNonce = const Value.absent(),
    this.payloadCiphertext = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  _CheckInsCompanion.insert({
    required String accountId,
    required String recordId,
    required int schemaVersion,
    required Uint8List payloadNonce,
    required Uint8List payloadCiphertext,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : accountId = Value(accountId),
        recordId = Value(recordId),
        schemaVersion = Value(schemaVersion),
        payloadNonce = Value(payloadNonce),
        payloadCiphertext = Value(payloadCiphertext),
        updatedAt = Value(updatedAt);
  static Insertable<_CheckIn> custom({
    Expression<String>? accountId,
    Expression<String>? recordId,
    Expression<int>? schemaVersion,
    Expression<Uint8List>? payloadNonce,
    Expression<Uint8List>? payloadCiphertext,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (recordId != null) 'record_id': recordId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (payloadNonce != null) 'payload_nonce': payloadNonce,
      if (payloadCiphertext != null) 'payload_ciphertext': payloadCiphertext,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  _CheckInsCompanion copyWith(
      {Value<String>? accountId,
      Value<String>? recordId,
      Value<int>? schemaVersion,
      Value<Uint8List>? payloadNonce,
      Value<Uint8List>? payloadCiphertext,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return _CheckInsCompanion(
      accountId: accountId ?? this.accountId,
      recordId: recordId ?? this.recordId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      payloadNonce: payloadNonce ?? this.payloadNonce,
      payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (payloadNonce.present) {
      map['payload_nonce'] = Variable<Uint8List>(payloadNonce.value);
    }
    if (payloadCiphertext.present) {
      map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('_CheckInsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('recordId: $recordId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $_PendingOperationsTable extends _PendingOperations
    with TableInfo<$_PendingOperationsTable, _PendingOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $_PendingOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationIdMeta =
      const VerificationMeta('operationId');
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
      'operation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _logicalClockMeta =
      const VerificationMeta('logicalClock');
  @override
  late final GeneratedColumn<int> logicalClock = GeneratedColumn<int>(
      'logical_clock', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadNonceMeta =
      const VerificationMeta('payloadNonce');
  @override
  late final GeneratedColumn<Uint8List> payloadNonce =
      GeneratedColumn<Uint8List>('payload_nonce', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _payloadCiphertextMeta =
      const VerificationMeta('payloadCiphertext');
  @override
  late final GeneratedColumn<Uint8List> payloadCiphertext =
      GeneratedColumn<Uint8List>('payload_ciphertext', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _isTombstoneMeta =
      const VerificationMeta('isTombstone');
  @override
  late final GeneratedColumn<bool> isTombstone = GeneratedColumn<bool>(
      'is_tombstone', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_tombstone" IN (0, 1))'));
  static const VerificationMeta _schemaVersionMeta =
      const VerificationMeta('schemaVersion');
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
      'schema_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _enqueuedAtMeta =
      const VerificationMeta('enqueuedAt');
  @override
  late final GeneratedColumn<DateTime> enqueuedAt = GeneratedColumn<DateTime>(
      'enqueued_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        accountId,
        operationId,
        recordId,
        deviceId,
        logicalClock,
        entityType,
        payloadNonce,
        payloadCiphertext,
        isTombstone,
        schemaVersion,
        enqueuedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_operations';
  @override
  VerificationContext validateIntegrity(Insertable<_PendingOperation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
          _operationIdMeta,
          operationId.isAcceptableOrUnknown(
              data['operation_id']!, _operationIdMeta));
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('logical_clock')) {
      context.handle(
          _logicalClockMeta,
          logicalClock.isAcceptableOrUnknown(
              data['logical_clock']!, _logicalClockMeta));
    } else if (isInserting) {
      context.missing(_logicalClockMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('payload_nonce')) {
      context.handle(
          _payloadNonceMeta,
          payloadNonce.isAcceptableOrUnknown(
              data['payload_nonce']!, _payloadNonceMeta));
    } else if (isInserting) {
      context.missing(_payloadNonceMeta);
    }
    if (data.containsKey('payload_ciphertext')) {
      context.handle(
          _payloadCiphertextMeta,
          payloadCiphertext.isAcceptableOrUnknown(
              data['payload_ciphertext']!, _payloadCiphertextMeta));
    } else if (isInserting) {
      context.missing(_payloadCiphertextMeta);
    }
    if (data.containsKey('is_tombstone')) {
      context.handle(
          _isTombstoneMeta,
          isTombstone.isAcceptableOrUnknown(
              data['is_tombstone']!, _isTombstoneMeta));
    } else if (isInserting) {
      context.missing(_isTombstoneMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
          _schemaVersionMeta,
          schemaVersion.isAcceptableOrUnknown(
              data['schema_version']!, _schemaVersionMeta));
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('enqueued_at')) {
      context.handle(
          _enqueuedAtMeta,
          enqueuedAt.isAcceptableOrUnknown(
              data['enqueued_at']!, _enqueuedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, operationId};
  @override
  _PendingOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return _PendingOperation(
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id'])!,
      operationId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_id'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      logicalClock: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}logical_clock'])!,
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      payloadNonce: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}payload_nonce'])!,
      payloadCiphertext: attachedDatabase.typeMapping.read(
          DriftSqlType.blob, data['${effectivePrefix}payload_ciphertext'])!,
      isTombstone: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_tombstone'])!,
      schemaVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}schema_version'])!,
      enqueuedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}enqueued_at'])!,
    );
  }

  @override
  $_PendingOperationsTable createAlias(String alias) {
    return $_PendingOperationsTable(attachedDatabase, alias);
  }
}

class _PendingOperation extends DataClass
    implements Insertable<_PendingOperation> {
  final String accountId;
  final String operationId;
  final String recordId;
  final String deviceId;
  final int logicalClock;
  final String entityType;
  final Uint8List payloadNonce;
  final Uint8List payloadCiphertext;
  final bool isTombstone;
  final int schemaVersion;
  final DateTime enqueuedAt;
  const _PendingOperation(
      {required this.accountId,
      required this.operationId,
      required this.recordId,
      required this.deviceId,
      required this.logicalClock,
      required this.entityType,
      required this.payloadNonce,
      required this.payloadCiphertext,
      required this.isTombstone,
      required this.schemaVersion,
      required this.enqueuedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['operation_id'] = Variable<String>(operationId);
    map['record_id'] = Variable<String>(recordId);
    map['device_id'] = Variable<String>(deviceId);
    map['logical_clock'] = Variable<int>(logicalClock);
    map['entity_type'] = Variable<String>(entityType);
    map['payload_nonce'] = Variable<Uint8List>(payloadNonce);
    map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext);
    map['is_tombstone'] = Variable<bool>(isTombstone);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['enqueued_at'] = Variable<DateTime>(enqueuedAt);
    return map;
  }

  _PendingOperationsCompanion toCompanion(bool nullToAbsent) {
    return _PendingOperationsCompanion(
      accountId: Value(accountId),
      operationId: Value(operationId),
      recordId: Value(recordId),
      deviceId: Value(deviceId),
      logicalClock: Value(logicalClock),
      entityType: Value(entityType),
      payloadNonce: Value(payloadNonce),
      payloadCiphertext: Value(payloadCiphertext),
      isTombstone: Value(isTombstone),
      schemaVersion: Value(schemaVersion),
      enqueuedAt: Value(enqueuedAt),
    );
  }

  factory _PendingOperation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return _PendingOperation(
      accountId: serializer.fromJson<String>(json['accountId']),
      operationId: serializer.fromJson<String>(json['operationId']),
      recordId: serializer.fromJson<String>(json['recordId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      logicalClock: serializer.fromJson<int>(json['logicalClock']),
      entityType: serializer.fromJson<String>(json['entityType']),
      payloadNonce: serializer.fromJson<Uint8List>(json['payloadNonce']),
      payloadCiphertext:
          serializer.fromJson<Uint8List>(json['payloadCiphertext']),
      isTombstone: serializer.fromJson<bool>(json['isTombstone']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      enqueuedAt: serializer.fromJson<DateTime>(json['enqueuedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'operationId': serializer.toJson<String>(operationId),
      'recordId': serializer.toJson<String>(recordId),
      'deviceId': serializer.toJson<String>(deviceId),
      'logicalClock': serializer.toJson<int>(logicalClock),
      'entityType': serializer.toJson<String>(entityType),
      'payloadNonce': serializer.toJson<Uint8List>(payloadNonce),
      'payloadCiphertext': serializer.toJson<Uint8List>(payloadCiphertext),
      'isTombstone': serializer.toJson<bool>(isTombstone),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'enqueuedAt': serializer.toJson<DateTime>(enqueuedAt),
    };
  }

  _PendingOperation copyWith(
          {String? accountId,
          String? operationId,
          String? recordId,
          String? deviceId,
          int? logicalClock,
          String? entityType,
          Uint8List? payloadNonce,
          Uint8List? payloadCiphertext,
          bool? isTombstone,
          int? schemaVersion,
          DateTime? enqueuedAt}) =>
      _PendingOperation(
        accountId: accountId ?? this.accountId,
        operationId: operationId ?? this.operationId,
        recordId: recordId ?? this.recordId,
        deviceId: deviceId ?? this.deviceId,
        logicalClock: logicalClock ?? this.logicalClock,
        entityType: entityType ?? this.entityType,
        payloadNonce: payloadNonce ?? this.payloadNonce,
        payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
        isTombstone: isTombstone ?? this.isTombstone,
        schemaVersion: schemaVersion ?? this.schemaVersion,
        enqueuedAt: enqueuedAt ?? this.enqueuedAt,
      );
  _PendingOperation copyWithCompanion(_PendingOperationsCompanion data) {
    return _PendingOperation(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      operationId:
          data.operationId.present ? data.operationId.value : this.operationId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      logicalClock: data.logicalClock.present
          ? data.logicalClock.value
          : this.logicalClock,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      payloadNonce: data.payloadNonce.present
          ? data.payloadNonce.value
          : this.payloadNonce,
      payloadCiphertext: data.payloadCiphertext.present
          ? data.payloadCiphertext.value
          : this.payloadCiphertext,
      isTombstone:
          data.isTombstone.present ? data.isTombstone.value : this.isTombstone,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      enqueuedAt:
          data.enqueuedAt.present ? data.enqueuedAt.value : this.enqueuedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('_PendingOperation(')
          ..write('accountId: $accountId, ')
          ..write('operationId: $operationId, ')
          ..write('recordId: $recordId, ')
          ..write('deviceId: $deviceId, ')
          ..write('logicalClock: $logicalClock, ')
          ..write('entityType: $entityType, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('isTombstone: $isTombstone, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('enqueuedAt: $enqueuedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      accountId,
      operationId,
      recordId,
      deviceId,
      logicalClock,
      entityType,
      $driftBlobEquality.hash(payloadNonce),
      $driftBlobEquality.hash(payloadCiphertext),
      isTombstone,
      schemaVersion,
      enqueuedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _PendingOperation &&
          other.accountId == this.accountId &&
          other.operationId == this.operationId &&
          other.recordId == this.recordId &&
          other.deviceId == this.deviceId &&
          other.logicalClock == this.logicalClock &&
          other.entityType == this.entityType &&
          $driftBlobEquality.equals(other.payloadNonce, this.payloadNonce) &&
          $driftBlobEquality.equals(
              other.payloadCiphertext, this.payloadCiphertext) &&
          other.isTombstone == this.isTombstone &&
          other.schemaVersion == this.schemaVersion &&
          other.enqueuedAt == this.enqueuedAt);
}

class _PendingOperationsCompanion extends UpdateCompanion<_PendingOperation> {
  final Value<String> accountId;
  final Value<String> operationId;
  final Value<String> recordId;
  final Value<String> deviceId;
  final Value<int> logicalClock;
  final Value<String> entityType;
  final Value<Uint8List> payloadNonce;
  final Value<Uint8List> payloadCiphertext;
  final Value<bool> isTombstone;
  final Value<int> schemaVersion;
  final Value<DateTime> enqueuedAt;
  final Value<int> rowid;
  const _PendingOperationsCompanion({
    this.accountId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.logicalClock = const Value.absent(),
    this.entityType = const Value.absent(),
    this.payloadNonce = const Value.absent(),
    this.payloadCiphertext = const Value.absent(),
    this.isTombstone = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.enqueuedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  _PendingOperationsCompanion.insert({
    required String accountId,
    required String operationId,
    required String recordId,
    required String deviceId,
    required int logicalClock,
    required String entityType,
    required Uint8List payloadNonce,
    required Uint8List payloadCiphertext,
    required bool isTombstone,
    required int schemaVersion,
    this.enqueuedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : accountId = Value(accountId),
        operationId = Value(operationId),
        recordId = Value(recordId),
        deviceId = Value(deviceId),
        logicalClock = Value(logicalClock),
        entityType = Value(entityType),
        payloadNonce = Value(payloadNonce),
        payloadCiphertext = Value(payloadCiphertext),
        isTombstone = Value(isTombstone),
        schemaVersion = Value(schemaVersion);
  static Insertable<_PendingOperation> custom({
    Expression<String>? accountId,
    Expression<String>? operationId,
    Expression<String>? recordId,
    Expression<String>? deviceId,
    Expression<int>? logicalClock,
    Expression<String>? entityType,
    Expression<Uint8List>? payloadNonce,
    Expression<Uint8List>? payloadCiphertext,
    Expression<bool>? isTombstone,
    Expression<int>? schemaVersion,
    Expression<DateTime>? enqueuedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (operationId != null) 'operation_id': operationId,
      if (recordId != null) 'record_id': recordId,
      if (deviceId != null) 'device_id': deviceId,
      if (logicalClock != null) 'logical_clock': logicalClock,
      if (entityType != null) 'entity_type': entityType,
      if (payloadNonce != null) 'payload_nonce': payloadNonce,
      if (payloadCiphertext != null) 'payload_ciphertext': payloadCiphertext,
      if (isTombstone != null) 'is_tombstone': isTombstone,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (enqueuedAt != null) 'enqueued_at': enqueuedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  _PendingOperationsCompanion copyWith(
      {Value<String>? accountId,
      Value<String>? operationId,
      Value<String>? recordId,
      Value<String>? deviceId,
      Value<int>? logicalClock,
      Value<String>? entityType,
      Value<Uint8List>? payloadNonce,
      Value<Uint8List>? payloadCiphertext,
      Value<bool>? isTombstone,
      Value<int>? schemaVersion,
      Value<DateTime>? enqueuedAt,
      Value<int>? rowid}) {
    return _PendingOperationsCompanion(
      accountId: accountId ?? this.accountId,
      operationId: operationId ?? this.operationId,
      recordId: recordId ?? this.recordId,
      deviceId: deviceId ?? this.deviceId,
      logicalClock: logicalClock ?? this.logicalClock,
      entityType: entityType ?? this.entityType,
      payloadNonce: payloadNonce ?? this.payloadNonce,
      payloadCiphertext: payloadCiphertext ?? this.payloadCiphertext,
      isTombstone: isTombstone ?? this.isTombstone,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (logicalClock.present) {
      map['logical_clock'] = Variable<int>(logicalClock.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (payloadNonce.present) {
      map['payload_nonce'] = Variable<Uint8List>(payloadNonce.value);
    }
    if (payloadCiphertext.present) {
      map['payload_ciphertext'] = Variable<Uint8List>(payloadCiphertext.value);
    }
    if (isTombstone.present) {
      map['is_tombstone'] = Variable<bool>(isTombstone.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (enqueuedAt.present) {
      map['enqueued_at'] = Variable<DateTime>(enqueuedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('_PendingOperationsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('operationId: $operationId, ')
          ..write('recordId: $recordId, ')
          ..write('deviceId: $deviceId, ')
          ..write('logicalClock: $logicalClock, ')
          ..write('entityType: $entityType, ')
          ..write('payloadNonce: $payloadNonce, ')
          ..write('payloadCiphertext: $payloadCiphertext, ')
          ..write('isTombstone: $isTombstone, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$_AccountDatabase extends GeneratedDatabase {
  _$_AccountDatabase(QueryExecutor e) : super(e);
  $_AccountDatabaseManager get managers => $_AccountDatabaseManager(this);
  late final $_TasksTable tasks = $_TasksTable(this);
  late final $_ScheduleBlocksTable scheduleBlocks = $_ScheduleBlocksTable(this);
  late final $_FocusSessionsTable focusSessions = $_FocusSessionsTable(this);
  late final $_CheckInsTable checkIns = $_CheckInsTable(this);
  late final $_PendingOperationsTable pendingOperations =
      $_PendingOperationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [tasks, scheduleBlocks, focusSessions, checkIns, pendingOperations];
}

typedef $$_TasksTableCreateCompanionBuilder = _TasksCompanion Function({
  required String accountId,
  required String recordId,
  required int schemaVersion,
  required Uint8List payloadNonce,
  required Uint8List payloadCiphertext,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$_TasksTableUpdateCompanionBuilder = _TasksCompanion Function({
  Value<String> accountId,
  Value<String> recordId,
  Value<int> schemaVersion,
  Value<Uint8List> payloadNonce,
  Value<Uint8List> payloadCiphertext,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$_TasksTableFilterComposer
    extends Composer<_$_AccountDatabase, $_TasksTable> {
  $$_TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$_TasksTableOrderingComposer
    extends Composer<_$_AccountDatabase, $_TasksTable> {
  $$_TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$_TasksTableAnnotationComposer
    extends Composer<_$_AccountDatabase, $_TasksTable> {
  $$_TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$_TasksTableTableManager extends RootTableManager<
    _$_AccountDatabase,
    $_TasksTable,
    _Task,
    $$_TasksTableFilterComposer,
    $$_TasksTableOrderingComposer,
    $$_TasksTableAnnotationComposer,
    $$_TasksTableCreateCompanionBuilder,
    $$_TasksTableUpdateCompanionBuilder,
    (_Task, BaseReferences<_$_AccountDatabase, $_TasksTable, _Task>),
    _Task,
    PrefetchHooks Function()> {
  $$_TasksTableTableManager(_$_AccountDatabase db, $_TasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$_TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$_TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$_TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> accountId = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<int> schemaVersion = const Value.absent(),
            Value<Uint8List> payloadNonce = const Value.absent(),
            Value<Uint8List> payloadCiphertext = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              _TasksCompanion(
            accountId: accountId,
            recordId: recordId,
            schemaVersion: schemaVersion,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String accountId,
            required String recordId,
            required int schemaVersion,
            required Uint8List payloadNonce,
            required Uint8List payloadCiphertext,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              _TasksCompanion.insert(
            accountId: accountId,
            recordId: recordId,
            schemaVersion: schemaVersion,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$_TasksTableProcessedTableManager = ProcessedTableManager<
    _$_AccountDatabase,
    $_TasksTable,
    _Task,
    $$_TasksTableFilterComposer,
    $$_TasksTableOrderingComposer,
    $$_TasksTableAnnotationComposer,
    $$_TasksTableCreateCompanionBuilder,
    $$_TasksTableUpdateCompanionBuilder,
    (_Task, BaseReferences<_$_AccountDatabase, $_TasksTable, _Task>),
    _Task,
    PrefetchHooks Function()>;
typedef $$_ScheduleBlocksTableCreateCompanionBuilder = _ScheduleBlocksCompanion
    Function({
  required String accountId,
  required String recordId,
  required int schemaVersion,
  required Uint8List payloadNonce,
  required Uint8List payloadCiphertext,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$_ScheduleBlocksTableUpdateCompanionBuilder = _ScheduleBlocksCompanion
    Function({
  Value<String> accountId,
  Value<String> recordId,
  Value<int> schemaVersion,
  Value<Uint8List> payloadNonce,
  Value<Uint8List> payloadCiphertext,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$_ScheduleBlocksTableFilterComposer
    extends Composer<_$_AccountDatabase, $_ScheduleBlocksTable> {
  $$_ScheduleBlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$_ScheduleBlocksTableOrderingComposer
    extends Composer<_$_AccountDatabase, $_ScheduleBlocksTable> {
  $$_ScheduleBlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$_ScheduleBlocksTableAnnotationComposer
    extends Composer<_$_AccountDatabase, $_ScheduleBlocksTable> {
  $$_ScheduleBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$_ScheduleBlocksTableTableManager extends RootTableManager<
    _$_AccountDatabase,
    $_ScheduleBlocksTable,
    _ScheduleBlock,
    $$_ScheduleBlocksTableFilterComposer,
    $$_ScheduleBlocksTableOrderingComposer,
    $$_ScheduleBlocksTableAnnotationComposer,
    $$_ScheduleBlocksTableCreateCompanionBuilder,
    $$_ScheduleBlocksTableUpdateCompanionBuilder,
    (
      _ScheduleBlock,
      BaseReferences<_$_AccountDatabase, $_ScheduleBlocksTable, _ScheduleBlock>
    ),
    _ScheduleBlock,
    PrefetchHooks Function()> {
  $$_ScheduleBlocksTableTableManager(
      _$_AccountDatabase db, $_ScheduleBlocksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$_ScheduleBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$_ScheduleBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$_ScheduleBlocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> accountId = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<int> schemaVersion = const Value.absent(),
            Value<Uint8List> payloadNonce = const Value.absent(),
            Value<Uint8List> payloadCiphertext = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              _ScheduleBlocksCompanion(
            accountId: accountId,
            recordId: recordId,
            schemaVersion: schemaVersion,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String accountId,
            required String recordId,
            required int schemaVersion,
            required Uint8List payloadNonce,
            required Uint8List payloadCiphertext,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              _ScheduleBlocksCompanion.insert(
            accountId: accountId,
            recordId: recordId,
            schemaVersion: schemaVersion,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$_ScheduleBlocksTableProcessedTableManager = ProcessedTableManager<
    _$_AccountDatabase,
    $_ScheduleBlocksTable,
    _ScheduleBlock,
    $$_ScheduleBlocksTableFilterComposer,
    $$_ScheduleBlocksTableOrderingComposer,
    $$_ScheduleBlocksTableAnnotationComposer,
    $$_ScheduleBlocksTableCreateCompanionBuilder,
    $$_ScheduleBlocksTableUpdateCompanionBuilder,
    (
      _ScheduleBlock,
      BaseReferences<_$_AccountDatabase, $_ScheduleBlocksTable, _ScheduleBlock>
    ),
    _ScheduleBlock,
    PrefetchHooks Function()>;
typedef $$_FocusSessionsTableCreateCompanionBuilder = _FocusSessionsCompanion
    Function({
  required String accountId,
  required String recordId,
  required int schemaVersion,
  required Uint8List payloadNonce,
  required Uint8List payloadCiphertext,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$_FocusSessionsTableUpdateCompanionBuilder = _FocusSessionsCompanion
    Function({
  Value<String> accountId,
  Value<String> recordId,
  Value<int> schemaVersion,
  Value<Uint8List> payloadNonce,
  Value<Uint8List> payloadCiphertext,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$_FocusSessionsTableFilterComposer
    extends Composer<_$_AccountDatabase, $_FocusSessionsTable> {
  $$_FocusSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$_FocusSessionsTableOrderingComposer
    extends Composer<_$_AccountDatabase, $_FocusSessionsTable> {
  $$_FocusSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$_FocusSessionsTableAnnotationComposer
    extends Composer<_$_AccountDatabase, $_FocusSessionsTable> {
  $$_FocusSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$_FocusSessionsTableTableManager extends RootTableManager<
    _$_AccountDatabase,
    $_FocusSessionsTable,
    _FocusSession,
    $$_FocusSessionsTableFilterComposer,
    $$_FocusSessionsTableOrderingComposer,
    $$_FocusSessionsTableAnnotationComposer,
    $$_FocusSessionsTableCreateCompanionBuilder,
    $$_FocusSessionsTableUpdateCompanionBuilder,
    (
      _FocusSession,
      BaseReferences<_$_AccountDatabase, $_FocusSessionsTable, _FocusSession>
    ),
    _FocusSession,
    PrefetchHooks Function()> {
  $$_FocusSessionsTableTableManager(
      _$_AccountDatabase db, $_FocusSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$_FocusSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$_FocusSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$_FocusSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> accountId = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<int> schemaVersion = const Value.absent(),
            Value<Uint8List> payloadNonce = const Value.absent(),
            Value<Uint8List> payloadCiphertext = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              _FocusSessionsCompanion(
            accountId: accountId,
            recordId: recordId,
            schemaVersion: schemaVersion,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String accountId,
            required String recordId,
            required int schemaVersion,
            required Uint8List payloadNonce,
            required Uint8List payloadCiphertext,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              _FocusSessionsCompanion.insert(
            accountId: accountId,
            recordId: recordId,
            schemaVersion: schemaVersion,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$_FocusSessionsTableProcessedTableManager = ProcessedTableManager<
    _$_AccountDatabase,
    $_FocusSessionsTable,
    _FocusSession,
    $$_FocusSessionsTableFilterComposer,
    $$_FocusSessionsTableOrderingComposer,
    $$_FocusSessionsTableAnnotationComposer,
    $$_FocusSessionsTableCreateCompanionBuilder,
    $$_FocusSessionsTableUpdateCompanionBuilder,
    (
      _FocusSession,
      BaseReferences<_$_AccountDatabase, $_FocusSessionsTable, _FocusSession>
    ),
    _FocusSession,
    PrefetchHooks Function()>;
typedef $$_CheckInsTableCreateCompanionBuilder = _CheckInsCompanion Function({
  required String accountId,
  required String recordId,
  required int schemaVersion,
  required Uint8List payloadNonce,
  required Uint8List payloadCiphertext,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$_CheckInsTableUpdateCompanionBuilder = _CheckInsCompanion Function({
  Value<String> accountId,
  Value<String> recordId,
  Value<int> schemaVersion,
  Value<Uint8List> payloadNonce,
  Value<Uint8List> payloadCiphertext,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$_CheckInsTableFilterComposer
    extends Composer<_$_AccountDatabase, $_CheckInsTable> {
  $$_CheckInsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$_CheckInsTableOrderingComposer
    extends Composer<_$_AccountDatabase, $_CheckInsTable> {
  $$_CheckInsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$_CheckInsTableAnnotationComposer
    extends Composer<_$_AccountDatabase, $_CheckInsTable> {
  $$_CheckInsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$_CheckInsTableTableManager extends RootTableManager<
    _$_AccountDatabase,
    $_CheckInsTable,
    _CheckIn,
    $$_CheckInsTableFilterComposer,
    $$_CheckInsTableOrderingComposer,
    $$_CheckInsTableAnnotationComposer,
    $$_CheckInsTableCreateCompanionBuilder,
    $$_CheckInsTableUpdateCompanionBuilder,
    (_CheckIn, BaseReferences<_$_AccountDatabase, $_CheckInsTable, _CheckIn>),
    _CheckIn,
    PrefetchHooks Function()> {
  $$_CheckInsTableTableManager(_$_AccountDatabase db, $_CheckInsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$_CheckInsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$_CheckInsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$_CheckInsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> accountId = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<int> schemaVersion = const Value.absent(),
            Value<Uint8List> payloadNonce = const Value.absent(),
            Value<Uint8List> payloadCiphertext = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              _CheckInsCompanion(
            accountId: accountId,
            recordId: recordId,
            schemaVersion: schemaVersion,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String accountId,
            required String recordId,
            required int schemaVersion,
            required Uint8List payloadNonce,
            required Uint8List payloadCiphertext,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              _CheckInsCompanion.insert(
            accountId: accountId,
            recordId: recordId,
            schemaVersion: schemaVersion,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$_CheckInsTableProcessedTableManager = ProcessedTableManager<
    _$_AccountDatabase,
    $_CheckInsTable,
    _CheckIn,
    $$_CheckInsTableFilterComposer,
    $$_CheckInsTableOrderingComposer,
    $$_CheckInsTableAnnotationComposer,
    $$_CheckInsTableCreateCompanionBuilder,
    $$_CheckInsTableUpdateCompanionBuilder,
    (_CheckIn, BaseReferences<_$_AccountDatabase, $_CheckInsTable, _CheckIn>),
    _CheckIn,
    PrefetchHooks Function()>;
typedef $$_PendingOperationsTableCreateCompanionBuilder
    = _PendingOperationsCompanion Function({
  required String accountId,
  required String operationId,
  required String recordId,
  required String deviceId,
  required int logicalClock,
  required String entityType,
  required Uint8List payloadNonce,
  required Uint8List payloadCiphertext,
  required bool isTombstone,
  required int schemaVersion,
  Value<DateTime> enqueuedAt,
  Value<int> rowid,
});
typedef $$_PendingOperationsTableUpdateCompanionBuilder
    = _PendingOperationsCompanion Function({
  Value<String> accountId,
  Value<String> operationId,
  Value<String> recordId,
  Value<String> deviceId,
  Value<int> logicalClock,
  Value<String> entityType,
  Value<Uint8List> payloadNonce,
  Value<Uint8List> payloadCiphertext,
  Value<bool> isTombstone,
  Value<int> schemaVersion,
  Value<DateTime> enqueuedAt,
  Value<int> rowid,
});

class $$_PendingOperationsTableFilterComposer
    extends Composer<_$_AccountDatabase, $_PendingOperationsTable> {
  $$_PendingOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get logicalClock => $composableBuilder(
      column: $table.logicalClock, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isTombstone => $composableBuilder(
      column: $table.isTombstone, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get enqueuedAt => $composableBuilder(
      column: $table.enqueuedAt, builder: (column) => ColumnFilters(column));
}

class $$_PendingOperationsTableOrderingComposer
    extends Composer<_$_AccountDatabase, $_PendingOperationsTable> {
  $$_PendingOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get logicalClock => $composableBuilder(
      column: $table.logicalClock,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isTombstone => $composableBuilder(
      column: $table.isTombstone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get enqueuedAt => $composableBuilder(
      column: $table.enqueuedAt, builder: (column) => ColumnOrderings(column));
}

class $$_PendingOperationsTableAnnotationComposer
    extends Composer<_$_AccountDatabase, $_PendingOperationsTable> {
  $$_PendingOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get logicalClock => $composableBuilder(
      column: $table.logicalClock, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadNonce => $composableBuilder(
      column: $table.payloadNonce, builder: (column) => column);

  GeneratedColumn<Uint8List> get payloadCiphertext => $composableBuilder(
      column: $table.payloadCiphertext, builder: (column) => column);

  GeneratedColumn<bool> get isTombstone => $composableBuilder(
      column: $table.isTombstone, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
      column: $table.schemaVersion, builder: (column) => column);

  GeneratedColumn<DateTime> get enqueuedAt => $composableBuilder(
      column: $table.enqueuedAt, builder: (column) => column);
}

class $$_PendingOperationsTableTableManager extends RootTableManager<
    _$_AccountDatabase,
    $_PendingOperationsTable,
    _PendingOperation,
    $$_PendingOperationsTableFilterComposer,
    $$_PendingOperationsTableOrderingComposer,
    $$_PendingOperationsTableAnnotationComposer,
    $$_PendingOperationsTableCreateCompanionBuilder,
    $$_PendingOperationsTableUpdateCompanionBuilder,
    (
      _PendingOperation,
      BaseReferences<_$_AccountDatabase, $_PendingOperationsTable,
          _PendingOperation>
    ),
    _PendingOperation,
    PrefetchHooks Function()> {
  $$_PendingOperationsTableTableManager(
      _$_AccountDatabase db, $_PendingOperationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$_PendingOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$_PendingOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$_PendingOperationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> accountId = const Value.absent(),
            Value<String> operationId = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<int> logicalClock = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<Uint8List> payloadNonce = const Value.absent(),
            Value<Uint8List> payloadCiphertext = const Value.absent(),
            Value<bool> isTombstone = const Value.absent(),
            Value<int> schemaVersion = const Value.absent(),
            Value<DateTime> enqueuedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              _PendingOperationsCompanion(
            accountId: accountId,
            operationId: operationId,
            recordId: recordId,
            deviceId: deviceId,
            logicalClock: logicalClock,
            entityType: entityType,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            isTombstone: isTombstone,
            schemaVersion: schemaVersion,
            enqueuedAt: enqueuedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String accountId,
            required String operationId,
            required String recordId,
            required String deviceId,
            required int logicalClock,
            required String entityType,
            required Uint8List payloadNonce,
            required Uint8List payloadCiphertext,
            required bool isTombstone,
            required int schemaVersion,
            Value<DateTime> enqueuedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              _PendingOperationsCompanion.insert(
            accountId: accountId,
            operationId: operationId,
            recordId: recordId,
            deviceId: deviceId,
            logicalClock: logicalClock,
            entityType: entityType,
            payloadNonce: payloadNonce,
            payloadCiphertext: payloadCiphertext,
            isTombstone: isTombstone,
            schemaVersion: schemaVersion,
            enqueuedAt: enqueuedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$_PendingOperationsTableProcessedTableManager = ProcessedTableManager<
    _$_AccountDatabase,
    $_PendingOperationsTable,
    _PendingOperation,
    $$_PendingOperationsTableFilterComposer,
    $$_PendingOperationsTableOrderingComposer,
    $$_PendingOperationsTableAnnotationComposer,
    $$_PendingOperationsTableCreateCompanionBuilder,
    $$_PendingOperationsTableUpdateCompanionBuilder,
    (
      _PendingOperation,
      BaseReferences<_$_AccountDatabase, $_PendingOperationsTable,
          _PendingOperation>
    ),
    _PendingOperation,
    PrefetchHooks Function()>;

class $_AccountDatabaseManager {
  final _$_AccountDatabase _db;
  $_AccountDatabaseManager(this._db);
  $$_TasksTableTableManager get tasks =>
      $$_TasksTableTableManager(_db, _db.tasks);
  $$_ScheduleBlocksTableTableManager get scheduleBlocks =>
      $$_ScheduleBlocksTableTableManager(_db, _db.scheduleBlocks);
  $$_FocusSessionsTableTableManager get focusSessions =>
      $$_FocusSessionsTableTableManager(_db, _db.focusSessions);
  $$_CheckInsTableTableManager get checkIns =>
      $$_CheckInsTableTableManager(_db, _db.checkIns);
  $$_PendingOperationsTableTableManager get pendingOperations =>
      $$_PendingOperationsTableTableManager(_db, _db.pendingOperations);
}
