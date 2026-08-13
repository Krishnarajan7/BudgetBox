// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AccountKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<AccountKind>($AccountsTable.$converterkind);
  static const VerificationMeta _balancePaiseMeta = const VerificationMeta(
    'balancePaise',
  );
  @override
  late final GeneratedColumn<int> balancePaise = GeneratedColumn<int>(
    'balance_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _asOfMeta = const VerificationMeta('asOf');
  @override
  late final GeneratedColumn<DateTime> asOf = GeneratedColumn<DateTime>(
    'as_of',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    kind,
    balancePaise,
    asOf,
    sortOrder,
    archived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('balance_paise')) {
      context.handle(
        _balancePaiseMeta,
        balancePaise.isAcceptableOrUnknown(
          data['balance_paise']!,
          _balancePaiseMeta,
        ),
      );
    }
    if (data.containsKey('as_of')) {
      context.handle(
        _asOfMeta,
        asOf.isAcceptableOrUnknown(data['as_of']!, _asOfMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: $AccountsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      balancePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balance_paise'],
      )!,
      asOf: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}as_of'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AccountKind, int, int> $converterkind =
      const EnumIndexConverter<AccountKind>(AccountKind.values);
}

class Account extends DataClass implements Insertable<Account> {
  final int id;
  final String name;
  final AccountKind kind;
  final int balancePaise;

  /// When the balance was last confirmed true — drives the staleness cue.
  final DateTime asOf;
  final int sortOrder;
  final bool archived;
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.balancePaise,
    required this.asOf,
    required this.sortOrder,
    required this.archived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    {
      map['kind'] = Variable<int>($AccountsTable.$converterkind.toSql(kind));
    }
    map['balance_paise'] = Variable<int>(balancePaise);
    map['as_of'] = Variable<DateTime>(asOf);
    map['sort_order'] = Variable<int>(sortOrder);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      balancePaise: Value(balancePaise),
      asOf: Value(asOf),
      sortOrder: Value(sortOrder),
      archived: Value(archived),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: $AccountsTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      balancePaise: serializer.fromJson<int>(json['balancePaise']),
      asOf: serializer.fromJson<DateTime>(json['asOf']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<int>(
        $AccountsTable.$converterkind.toJson(kind),
      ),
      'balancePaise': serializer.toJson<int>(balancePaise),
      'asOf': serializer.toJson<DateTime>(asOf),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  Account copyWith({
    int? id,
    String? name,
    AccountKind? kind,
    int? balancePaise,
    DateTime? asOf,
    int? sortOrder,
    bool? archived,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    balancePaise: balancePaise ?? this.balancePaise,
    asOf: asOf ?? this.asOf,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      balancePaise: data.balancePaise.present
          ? data.balancePaise.value
          : this.balancePaise,
      asOf: data.asOf.present ? data.asOf.value : this.asOf,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('balancePaise: $balancePaise, ')
          ..write('asOf: $asOf, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, kind, balancePaise, asOf, sortOrder, archived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.balancePaise == this.balancePaise &&
          other.asOf == this.asOf &&
          other.sortOrder == this.sortOrder &&
          other.archived == this.archived);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<int> id;
  final Value<String> name;
  final Value<AccountKind> kind;
  final Value<int> balancePaise;
  final Value<DateTime> asOf;
  final Value<int> sortOrder;
  final Value<bool> archived;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.balancePaise = const Value.absent(),
    this.asOf = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archived = const Value.absent(),
  });
  AccountsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required AccountKind kind,
    this.balancePaise = const Value.absent(),
    this.asOf = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archived = const Value.absent(),
  }) : name = Value(name),
       kind = Value(kind);
  static Insertable<Account> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? kind,
    Expression<int>? balancePaise,
    Expression<DateTime>? asOf,
    Expression<int>? sortOrder,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (balancePaise != null) 'balance_paise': balancePaise,
      if (asOf != null) 'as_of': asOf,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archived != null) 'archived': archived,
    });
  }

  AccountsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<AccountKind>? kind,
    Value<int>? balancePaise,
    Value<DateTime>? asOf,
    Value<int>? sortOrder,
    Value<bool>? archived,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      balancePaise: balancePaise ?? this.balancePaise,
      asOf: asOf ?? this.asOf,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $AccountsTable.$converterkind.toSql(kind.value),
      );
    }
    if (balancePaise.present) {
      map['balance_paise'] = Variable<int>(balancePaise.value);
    }
    if (asOf.present) {
      map['as_of'] = Variable<DateTime>(asOf.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('balancePaise: $balancePaise, ')
          ..write('asOf: $asOf, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('circle'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<CategoryKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<CategoryKind>($CategoriesTable.$converterkind);
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    icon,
    kind,
    sortOrder,
    archived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      kind: $CategoriesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<CategoryKind, int, int> $converterkind =
      const EnumIndexConverter<CategoryKind>(CategoryKind.values);
}

class Category extends DataClass implements Insertable<Category> {
  final int id;
  final String name;

  /// A key into [LedgerIcons.catalogue] — categories wear drawn marks, not
  /// typed ones.
  final String icon;
  final CategoryKind kind;
  final int sortOrder;
  final bool archived;
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    required this.sortOrder,
    required this.archived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    {
      map['kind'] = Variable<int>($CategoriesTable.$converterkind.toSql(kind));
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      kind: Value(kind),
      sortOrder: Value(sortOrder),
      archived: Value(archived),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      kind: $CategoriesTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'kind': serializer.toJson<int>(
        $CategoriesTable.$converterkind.toJson(kind),
      ),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  Category copyWith({
    int? id,
    String? name,
    String? icon,
    CategoryKind? kind,
    int? sortOrder,
    bool? archived,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    kind: kind ?? this.kind,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      kind: data.kind.present ? data.kind.value : this.kind,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('kind: $kind, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, icon, kind, sortOrder, archived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.kind == this.kind &&
          other.sortOrder == this.sortOrder &&
          other.archived == this.archived);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<CategoryKind> kind;
  final Value<int> sortOrder;
  final Value<bool> archived;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.kind = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archived = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.icon = const Value.absent(),
    required CategoryKind kind,
    this.sortOrder = const Value.absent(),
    this.archived = const Value.absent(),
  }) : name = Value(name),
       kind = Value(kind);
  static Insertable<Category> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<int>? kind,
    Expression<int>? sortOrder,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (kind != null) 'kind': kind,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archived != null) 'archived': archived,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? icon,
    Value<CategoryKind>? kind,
    Value<int>? sortOrder,
    Value<bool>? archived,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      kind: kind ?? this.kind,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $CategoriesTable.$converterkind.toSql(kind.value),
      );
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('kind: $kind, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $GoalsTable extends Goals with TableInfo<$GoalsTable, Goal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetPaiseMeta = const VerificationMeta(
    'targetPaise',
  );
  @override
  late final GeneratedColumn<int> targetPaise = GeneratedColumn<int>(
    'target_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<GoalKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<GoalKind>($GoalsTable.$converterkind);
  static const VerificationMeta _targetDateMeta = const VerificationMeta(
    'targetDate',
  );
  @override
  late final GeneratedColumn<String> targetDate = GeneratedColumn<String>(
    'target_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _monthlyPaiseMeta = const VerificationMeta(
    'monthlyPaise',
  );
  @override
  late final GeneratedColumn<int> monthlyPaise = GeneratedColumn<int>(
    'monthly_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    targetPaise,
    kind,
    targetDate,
    monthlyPaise,
    archived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goals';
  @override
  VerificationContext validateIntegrity(
    Insertable<Goal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('target_paise')) {
      context.handle(
        _targetPaiseMeta,
        targetPaise.isAcceptableOrUnknown(
          data['target_paise']!,
          _targetPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetPaiseMeta);
    }
    if (data.containsKey('target_date')) {
      context.handle(
        _targetDateMeta,
        targetDate.isAcceptableOrUnknown(data['target_date']!, _targetDateMeta),
      );
    }
    if (data.containsKey('monthly_paise')) {
      context.handle(
        _monthlyPaiseMeta,
        monthlyPaise.isAcceptableOrUnknown(
          data['monthly_paise']!,
          _monthlyPaiseMeta,
        ),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Goal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Goal(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      targetPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_paise'],
      )!,
      kind: $GoalsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      targetDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_date'],
      ),
      monthlyPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}monthly_paise'],
      ),
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
    );
  }

  @override
  $GoalsTable createAlias(String alias) {
    return $GoalsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<GoalKind, int, int> $converterkind =
      const EnumIndexConverter<GoalKind>(GoalKind.values);
}

class Goal extends DataClass implements Insertable<Goal> {
  final int id;
  final String name;
  final int targetPaise;
  final GoalKind kind;
  final String? targetDate;
  final int? monthlyPaise;
  final bool archived;
  const Goal({
    required this.id,
    required this.name,
    required this.targetPaise,
    required this.kind,
    this.targetDate,
    this.monthlyPaise,
    required this.archived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['target_paise'] = Variable<int>(targetPaise);
    {
      map['kind'] = Variable<int>($GoalsTable.$converterkind.toSql(kind));
    }
    if (!nullToAbsent || targetDate != null) {
      map['target_date'] = Variable<String>(targetDate);
    }
    if (!nullToAbsent || monthlyPaise != null) {
      map['monthly_paise'] = Variable<int>(monthlyPaise);
    }
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  GoalsCompanion toCompanion(bool nullToAbsent) {
    return GoalsCompanion(
      id: Value(id),
      name: Value(name),
      targetPaise: Value(targetPaise),
      kind: Value(kind),
      targetDate: targetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDate),
      monthlyPaise: monthlyPaise == null && nullToAbsent
          ? const Value.absent()
          : Value(monthlyPaise),
      archived: Value(archived),
    );
  }

  factory Goal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Goal(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      targetPaise: serializer.fromJson<int>(json['targetPaise']),
      kind: $GoalsTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      targetDate: serializer.fromJson<String?>(json['targetDate']),
      monthlyPaise: serializer.fromJson<int?>(json['monthlyPaise']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'targetPaise': serializer.toJson<int>(targetPaise),
      'kind': serializer.toJson<int>($GoalsTable.$converterkind.toJson(kind)),
      'targetDate': serializer.toJson<String?>(targetDate),
      'monthlyPaise': serializer.toJson<int?>(monthlyPaise),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  Goal copyWith({
    int? id,
    String? name,
    int? targetPaise,
    GoalKind? kind,
    Value<String?> targetDate = const Value.absent(),
    Value<int?> monthlyPaise = const Value.absent(),
    bool? archived,
  }) => Goal(
    id: id ?? this.id,
    name: name ?? this.name,
    targetPaise: targetPaise ?? this.targetPaise,
    kind: kind ?? this.kind,
    targetDate: targetDate.present ? targetDate.value : this.targetDate,
    monthlyPaise: monthlyPaise.present ? monthlyPaise.value : this.monthlyPaise,
    archived: archived ?? this.archived,
  );
  Goal copyWithCompanion(GoalsCompanion data) {
    return Goal(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      targetPaise: data.targetPaise.present
          ? data.targetPaise.value
          : this.targetPaise,
      kind: data.kind.present ? data.kind.value : this.kind,
      targetDate: data.targetDate.present
          ? data.targetDate.value
          : this.targetDate,
      monthlyPaise: data.monthlyPaise.present
          ? data.monthlyPaise.value
          : this.monthlyPaise,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Goal(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('targetPaise: $targetPaise, ')
          ..write('kind: $kind, ')
          ..write('targetDate: $targetDate, ')
          ..write('monthlyPaise: $monthlyPaise, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    targetPaise,
    kind,
    targetDate,
    monthlyPaise,
    archived,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Goal &&
          other.id == this.id &&
          other.name == this.name &&
          other.targetPaise == this.targetPaise &&
          other.kind == this.kind &&
          other.targetDate == this.targetDate &&
          other.monthlyPaise == this.monthlyPaise &&
          other.archived == this.archived);
}

class GoalsCompanion extends UpdateCompanion<Goal> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> targetPaise;
  final Value<GoalKind> kind;
  final Value<String?> targetDate;
  final Value<int?> monthlyPaise;
  final Value<bool> archived;
  const GoalsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.targetPaise = const Value.absent(),
    this.kind = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.monthlyPaise = const Value.absent(),
    this.archived = const Value.absent(),
  });
  GoalsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int targetPaise,
    required GoalKind kind,
    this.targetDate = const Value.absent(),
    this.monthlyPaise = const Value.absent(),
    this.archived = const Value.absent(),
  }) : name = Value(name),
       targetPaise = Value(targetPaise),
       kind = Value(kind);
  static Insertable<Goal> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? targetPaise,
    Expression<int>? kind,
    Expression<String>? targetDate,
    Expression<int>? monthlyPaise,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (targetPaise != null) 'target_paise': targetPaise,
      if (kind != null) 'kind': kind,
      if (targetDate != null) 'target_date': targetDate,
      if (monthlyPaise != null) 'monthly_paise': monthlyPaise,
      if (archived != null) 'archived': archived,
    });
  }

  GoalsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? targetPaise,
    Value<GoalKind>? kind,
    Value<String?>? targetDate,
    Value<int?>? monthlyPaise,
    Value<bool>? archived,
  }) {
    return GoalsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      targetPaise: targetPaise ?? this.targetPaise,
      kind: kind ?? this.kind,
      targetDate: targetDate ?? this.targetDate,
      monthlyPaise: monthlyPaise ?? this.monthlyPaise,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (targetPaise.present) {
      map['target_paise'] = Variable<int>(targetPaise.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>($GoalsTable.$converterkind.toSql(kind.value));
    }
    if (targetDate.present) {
      map['target_date'] = Variable<String>(targetDate.value);
    }
    if (monthlyPaise.present) {
      map['monthly_paise'] = Variable<int>(monthlyPaise.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoalsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('targetPaise: $targetPaise, ')
          ..write('kind: $kind, ')
          ..write('targetDate: $targetDate, ')
          ..write('monthlyPaise: $monthlyPaise, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $RecurringsTable extends Recurrings
    with TableInfo<$RecurringsTable, Recurring> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecurringsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<RecurringKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<RecurringKind>($RecurringsTable.$converterkind);
  static const VerificationMeta _everyMonthsMeta = const VerificationMeta(
    'everyMonths',
  );
  @override
  late final GeneratedColumn<int> everyMonths = GeneratedColumn<int>(
    'every_months',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _dayOfMonthMeta = const VerificationMeta(
    'dayOfMonth',
  );
  @override
  late final GeneratedColumn<int> dayOfMonth = GeneratedColumn<int>(
    'day_of_month',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextDueMeta = const VerificationMeta(
    'nextDue',
  );
  @override
  late final GeneratedColumn<String> nextDue = GeneratedColumn<String>(
    'next_due',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    amountPaise,
    categoryId,
    accountId,
    kind,
    everyMonths,
    dayOfMonth,
    nextDue,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recurrings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Recurring> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('every_months')) {
      context.handle(
        _everyMonthsMeta,
        everyMonths.isAcceptableOrUnknown(
          data['every_months']!,
          _everyMonthsMeta,
        ),
      );
    }
    if (data.containsKey('day_of_month')) {
      context.handle(
        _dayOfMonthMeta,
        dayOfMonth.isAcceptableOrUnknown(
          data['day_of_month']!,
          _dayOfMonthMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dayOfMonthMeta);
    }
    if (data.containsKey('next_due')) {
      context.handle(
        _nextDueMeta,
        nextDue.isAcceptableOrUnknown(data['next_due']!, _nextDueMeta),
      );
    } else if (isInserting) {
      context.missing(_nextDueMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Recurring map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Recurring(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      ),
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}account_id'],
      )!,
      kind: $RecurringsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      everyMonths: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}every_months'],
      )!,
      dayOfMonth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_of_month'],
      )!,
      nextDue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_due'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $RecurringsTable createAlias(String alias) {
    return $RecurringsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<RecurringKind, int, int> $converterkind =
      const EnumIndexConverter<RecurringKind>(RecurringKind.values);
}

class Recurring extends DataClass implements Insertable<Recurring> {
  final int id;
  final String title;
  final int amountPaise;
  final int? categoryId;
  final int accountId;
  final RecurringKind kind;

  /// Every n months (1 = monthly, 12 = yearly).
  final int everyMonths;

  /// Day of month it lands (clamped to month length).
  final int dayOfMonth;
  final String nextDue;
  final bool active;
  const Recurring({
    required this.id,
    required this.title,
    required this.amountPaise,
    this.categoryId,
    required this.accountId,
    required this.kind,
    required this.everyMonths,
    required this.dayOfMonth,
    required this.nextDue,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['amount_paise'] = Variable<int>(amountPaise);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['account_id'] = Variable<int>(accountId);
    {
      map['kind'] = Variable<int>($RecurringsTable.$converterkind.toSql(kind));
    }
    map['every_months'] = Variable<int>(everyMonths);
    map['day_of_month'] = Variable<int>(dayOfMonth);
    map['next_due'] = Variable<String>(nextDue);
    map['active'] = Variable<bool>(active);
    return map;
  }

  RecurringsCompanion toCompanion(bool nullToAbsent) {
    return RecurringsCompanion(
      id: Value(id),
      title: Value(title),
      amountPaise: Value(amountPaise),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      accountId: Value(accountId),
      kind: Value(kind),
      everyMonths: Value(everyMonths),
      dayOfMonth: Value(dayOfMonth),
      nextDue: Value(nextDue),
      active: Value(active),
    );
  }

  factory Recurring.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Recurring(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      accountId: serializer.fromJson<int>(json['accountId']),
      kind: $RecurringsTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      everyMonths: serializer.fromJson<int>(json['everyMonths']),
      dayOfMonth: serializer.fromJson<int>(json['dayOfMonth']),
      nextDue: serializer.fromJson<String>(json['nextDue']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'categoryId': serializer.toJson<int?>(categoryId),
      'accountId': serializer.toJson<int>(accountId),
      'kind': serializer.toJson<int>(
        $RecurringsTable.$converterkind.toJson(kind),
      ),
      'everyMonths': serializer.toJson<int>(everyMonths),
      'dayOfMonth': serializer.toJson<int>(dayOfMonth),
      'nextDue': serializer.toJson<String>(nextDue),
      'active': serializer.toJson<bool>(active),
    };
  }

  Recurring copyWith({
    int? id,
    String? title,
    int? amountPaise,
    Value<int?> categoryId = const Value.absent(),
    int? accountId,
    RecurringKind? kind,
    int? everyMonths,
    int? dayOfMonth,
    String? nextDue,
    bool? active,
  }) => Recurring(
    id: id ?? this.id,
    title: title ?? this.title,
    amountPaise: amountPaise ?? this.amountPaise,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    accountId: accountId ?? this.accountId,
    kind: kind ?? this.kind,
    everyMonths: everyMonths ?? this.everyMonths,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    nextDue: nextDue ?? this.nextDue,
    active: active ?? this.active,
  );
  Recurring copyWithCompanion(RecurringsCompanion data) {
    return Recurring(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      kind: data.kind.present ? data.kind.value : this.kind,
      everyMonths: data.everyMonths.present
          ? data.everyMonths.value
          : this.everyMonths,
      dayOfMonth: data.dayOfMonth.present
          ? data.dayOfMonth.value
          : this.dayOfMonth,
      nextDue: data.nextDue.present ? data.nextDue.value : this.nextDue,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Recurring(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('kind: $kind, ')
          ..write('everyMonths: $everyMonths, ')
          ..write('dayOfMonth: $dayOfMonth, ')
          ..write('nextDue: $nextDue, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    amountPaise,
    categoryId,
    accountId,
    kind,
    everyMonths,
    dayOfMonth,
    nextDue,
    active,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Recurring &&
          other.id == this.id &&
          other.title == this.title &&
          other.amountPaise == this.amountPaise &&
          other.categoryId == this.categoryId &&
          other.accountId == this.accountId &&
          other.kind == this.kind &&
          other.everyMonths == this.everyMonths &&
          other.dayOfMonth == this.dayOfMonth &&
          other.nextDue == this.nextDue &&
          other.active == this.active);
}

class RecurringsCompanion extends UpdateCompanion<Recurring> {
  final Value<int> id;
  final Value<String> title;
  final Value<int> amountPaise;
  final Value<int?> categoryId;
  final Value<int> accountId;
  final Value<RecurringKind> kind;
  final Value<int> everyMonths;
  final Value<int> dayOfMonth;
  final Value<String> nextDue;
  final Value<bool> active;
  const RecurringsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.kind = const Value.absent(),
    this.everyMonths = const Value.absent(),
    this.dayOfMonth = const Value.absent(),
    this.nextDue = const Value.absent(),
    this.active = const Value.absent(),
  });
  RecurringsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required int amountPaise,
    this.categoryId = const Value.absent(),
    required int accountId,
    required RecurringKind kind,
    this.everyMonths = const Value.absent(),
    required int dayOfMonth,
    required String nextDue,
    this.active = const Value.absent(),
  }) : title = Value(title),
       amountPaise = Value(amountPaise),
       accountId = Value(accountId),
       kind = Value(kind),
       dayOfMonth = Value(dayOfMonth),
       nextDue = Value(nextDue);
  static Insertable<Recurring> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<int>? amountPaise,
    Expression<int>? categoryId,
    Expression<int>? accountId,
    Expression<int>? kind,
    Expression<int>? everyMonths,
    Expression<int>? dayOfMonth,
    Expression<String>? nextDue,
    Expression<bool>? active,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (categoryId != null) 'category_id': categoryId,
      if (accountId != null) 'account_id': accountId,
      if (kind != null) 'kind': kind,
      if (everyMonths != null) 'every_months': everyMonths,
      if (dayOfMonth != null) 'day_of_month': dayOfMonth,
      if (nextDue != null) 'next_due': nextDue,
      if (active != null) 'active': active,
    });
  }

  RecurringsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<int>? amountPaise,
    Value<int?>? categoryId,
    Value<int>? accountId,
    Value<RecurringKind>? kind,
    Value<int>? everyMonths,
    Value<int>? dayOfMonth,
    Value<String>? nextDue,
    Value<bool>? active,
  }) {
    return RecurringsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      amountPaise: amountPaise ?? this.amountPaise,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      kind: kind ?? this.kind,
      everyMonths: everyMonths ?? this.everyMonths,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      nextDue: nextDue ?? this.nextDue,
      active: active ?? this.active,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $RecurringsTable.$converterkind.toSql(kind.value),
      );
    }
    if (everyMonths.present) {
      map['every_months'] = Variable<int>(everyMonths.value);
    }
    if (dayOfMonth.present) {
      map['day_of_month'] = Variable<int>(dayOfMonth.value);
    }
    if (nextDue.present) {
      map['next_due'] = Variable<String>(nextDue.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecurringsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('kind: $kind, ')
          ..write('everyMonths: $everyMonths, ')
          ..write('dayOfMonth: $dayOfMonth, ')
          ..write('nextDue: $nextDue, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }
}

class $TxnsTable extends Txns with TableInfo<$TxnsTable, Txn> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TxnsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TxnType, int> type =
      GeneratedColumn<int>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<TxnType>($TxnsTable.$convertertype);
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _toAccountIdMeta = const VerificationMeta(
    'toAccountId',
  );
  @override
  late final GeneratedColumn<int> toAccountId = GeneratedColumn<int>(
    'to_account_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _goalIdMeta = const VerificationMeta('goalId');
  @override
  late final GeneratedColumn<int> goalId = GeneratedColumn<int>(
    'goal_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES goals (id)',
    ),
  );
  static const VerificationMeta _recurringIdMeta = const VerificationMeta(
    'recurringId',
  );
  @override
  late final GeneratedColumn<int> recurringId = GeneratedColumn<int>(
    'recurring_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recurrings (id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    amountPaise,
    type,
    categoryId,
    accountId,
    toAccountId,
    title,
    note,
    at,
    goalId,
    recurringId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'txns';
  @override
  VerificationContext validateIntegrity(
    Insertable<Txn> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('to_account_id')) {
      context.handle(
        _toAccountIdMeta,
        toAccountId.isAcceptableOrUnknown(
          data['to_account_id']!,
          _toAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('goal_id')) {
      context.handle(
        _goalIdMeta,
        goalId.isAcceptableOrUnknown(data['goal_id']!, _goalIdMeta),
      );
    }
    if (data.containsKey('recurring_id')) {
      context.handle(
        _recurringIdMeta,
        recurringId.isAcceptableOrUnknown(
          data['recurring_id']!,
          _recurringIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Txn map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Txn(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      type: $TxnsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}type'],
        )!,
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      ),
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}account_id'],
      )!,
      toAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}to_account_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
      goalId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}goal_id'],
      ),
      recurringId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recurring_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TxnsTable createAlias(String alias) {
    return $TxnsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TxnType, int, int> $convertertype =
      const EnumIndexConverter<TxnType>(TxnType.values);
}

class Txn extends DataClass implements Insertable<Txn> {
  final int id;
  final int amountPaise;
  final TxnType type;
  final int? categoryId;
  final int accountId;

  /// Transfer destination; null for expense/income.
  final int? toAccountId;
  final String title;
  final String? note;
  final DateTime at;
  final int? goalId;
  final int? recurringId;
  final DateTime createdAt;
  const Txn({
    required this.id,
    required this.amountPaise,
    required this.type,
    this.categoryId,
    required this.accountId,
    this.toAccountId,
    required this.title,
    this.note,
    required this.at,
    this.goalId,
    this.recurringId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['amount_paise'] = Variable<int>(amountPaise);
    {
      map['type'] = Variable<int>($TxnsTable.$convertertype.toSql(type));
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['account_id'] = Variable<int>(accountId);
    if (!nullToAbsent || toAccountId != null) {
      map['to_account_id'] = Variable<int>(toAccountId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['at'] = Variable<DateTime>(at);
    if (!nullToAbsent || goalId != null) {
      map['goal_id'] = Variable<int>(goalId);
    }
    if (!nullToAbsent || recurringId != null) {
      map['recurring_id'] = Variable<int>(recurringId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TxnsCompanion toCompanion(bool nullToAbsent) {
    return TxnsCompanion(
      id: Value(id),
      amountPaise: Value(amountPaise),
      type: Value(type),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      accountId: Value(accountId),
      toAccountId: toAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(toAccountId),
      title: Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      at: Value(at),
      goalId: goalId == null && nullToAbsent
          ? const Value.absent()
          : Value(goalId),
      recurringId: recurringId == null && nullToAbsent
          ? const Value.absent()
          : Value(recurringId),
      createdAt: Value(createdAt),
    );
  }

  factory Txn.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Txn(
      id: serializer.fromJson<int>(json['id']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      type: $TxnsTable.$convertertype.fromJson(
        serializer.fromJson<int>(json['type']),
      ),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      accountId: serializer.fromJson<int>(json['accountId']),
      toAccountId: serializer.fromJson<int?>(json['toAccountId']),
      title: serializer.fromJson<String>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      at: serializer.fromJson<DateTime>(json['at']),
      goalId: serializer.fromJson<int?>(json['goalId']),
      recurringId: serializer.fromJson<int?>(json['recurringId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'type': serializer.toJson<int>($TxnsTable.$convertertype.toJson(type)),
      'categoryId': serializer.toJson<int?>(categoryId),
      'accountId': serializer.toJson<int>(accountId),
      'toAccountId': serializer.toJson<int?>(toAccountId),
      'title': serializer.toJson<String>(title),
      'note': serializer.toJson<String?>(note),
      'at': serializer.toJson<DateTime>(at),
      'goalId': serializer.toJson<int?>(goalId),
      'recurringId': serializer.toJson<int?>(recurringId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Txn copyWith({
    int? id,
    int? amountPaise,
    TxnType? type,
    Value<int?> categoryId = const Value.absent(),
    int? accountId,
    Value<int?> toAccountId = const Value.absent(),
    String? title,
    Value<String?> note = const Value.absent(),
    DateTime? at,
    Value<int?> goalId = const Value.absent(),
    Value<int?> recurringId = const Value.absent(),
    DateTime? createdAt,
  }) => Txn(
    id: id ?? this.id,
    amountPaise: amountPaise ?? this.amountPaise,
    type: type ?? this.type,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    accountId: accountId ?? this.accountId,
    toAccountId: toAccountId.present ? toAccountId.value : this.toAccountId,
    title: title ?? this.title,
    note: note.present ? note.value : this.note,
    at: at ?? this.at,
    goalId: goalId.present ? goalId.value : this.goalId,
    recurringId: recurringId.present ? recurringId.value : this.recurringId,
    createdAt: createdAt ?? this.createdAt,
  );
  Txn copyWithCompanion(TxnsCompanion data) {
    return Txn(
      id: data.id.present ? data.id.value : this.id,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      type: data.type.present ? data.type.value : this.type,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      toAccountId: data.toAccountId.present
          ? data.toAccountId.value
          : this.toAccountId,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      at: data.at.present ? data.at.value : this.at,
      goalId: data.goalId.present ? data.goalId.value : this.goalId,
      recurringId: data.recurringId.present
          ? data.recurringId.value
          : this.recurringId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Txn(')
          ..write('id: $id, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('type: $type, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('at: $at, ')
          ..write('goalId: $goalId, ')
          ..write('recurringId: $recurringId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    amountPaise,
    type,
    categoryId,
    accountId,
    toAccountId,
    title,
    note,
    at,
    goalId,
    recurringId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Txn &&
          other.id == this.id &&
          other.amountPaise == this.amountPaise &&
          other.type == this.type &&
          other.categoryId == this.categoryId &&
          other.accountId == this.accountId &&
          other.toAccountId == this.toAccountId &&
          other.title == this.title &&
          other.note == this.note &&
          other.at == this.at &&
          other.goalId == this.goalId &&
          other.recurringId == this.recurringId &&
          other.createdAt == this.createdAt);
}

class TxnsCompanion extends UpdateCompanion<Txn> {
  final Value<int> id;
  final Value<int> amountPaise;
  final Value<TxnType> type;
  final Value<int?> categoryId;
  final Value<int> accountId;
  final Value<int?> toAccountId;
  final Value<String> title;
  final Value<String?> note;
  final Value<DateTime> at;
  final Value<int?> goalId;
  final Value<int?> recurringId;
  final Value<DateTime> createdAt;
  const TxnsCompanion({
    this.id = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.type = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.at = const Value.absent(),
    this.goalId = const Value.absent(),
    this.recurringId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TxnsCompanion.insert({
    this.id = const Value.absent(),
    required int amountPaise,
    required TxnType type,
    this.categoryId = const Value.absent(),
    required int accountId,
    this.toAccountId = const Value.absent(),
    required String title,
    this.note = const Value.absent(),
    required DateTime at,
    this.goalId = const Value.absent(),
    this.recurringId = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : amountPaise = Value(amountPaise),
       type = Value(type),
       accountId = Value(accountId),
       title = Value(title),
       at = Value(at);
  static Insertable<Txn> custom({
    Expression<int>? id,
    Expression<int>? amountPaise,
    Expression<int>? type,
    Expression<int>? categoryId,
    Expression<int>? accountId,
    Expression<int>? toAccountId,
    Expression<String>? title,
    Expression<String>? note,
    Expression<DateTime>? at,
    Expression<int>? goalId,
    Expression<int>? recurringId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (type != null) 'type': type,
      if (categoryId != null) 'category_id': categoryId,
      if (accountId != null) 'account_id': accountId,
      if (toAccountId != null) 'to_account_id': toAccountId,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (at != null) 'at': at,
      if (goalId != null) 'goal_id': goalId,
      if (recurringId != null) 'recurring_id': recurringId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TxnsCompanion copyWith({
    Value<int>? id,
    Value<int>? amountPaise,
    Value<TxnType>? type,
    Value<int?>? categoryId,
    Value<int>? accountId,
    Value<int?>? toAccountId,
    Value<String>? title,
    Value<String?>? note,
    Value<DateTime>? at,
    Value<int?>? goalId,
    Value<int?>? recurringId,
    Value<DateTime>? createdAt,
  }) {
    return TxnsCompanion(
      id: id ?? this.id,
      amountPaise: amountPaise ?? this.amountPaise,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      toAccountId: toAccountId ?? this.toAccountId,
      title: title ?? this.title,
      note: note ?? this.note,
      at: at ?? this.at,
      goalId: goalId ?? this.goalId,
      recurringId: recurringId ?? this.recurringId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (type.present) {
      map['type'] = Variable<int>($TxnsTable.$convertertype.toSql(type.value));
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (toAccountId.present) {
      map['to_account_id'] = Variable<int>(toAccountId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    if (goalId.present) {
      map['goal_id'] = Variable<int>(goalId.value);
    }
    if (recurringId.present) {
      map['recurring_id'] = Variable<int>(recurringId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TxnsCompanion(')
          ..write('id: $id, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('type: $type, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('at: $at, ')
          ..write('goalId: $goalId, ')
          ..write('recurringId: $recurringId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $BudgetsTable extends Budgets with TableInfo<$BudgetsTable, Budget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _limitPaiseMeta = const VerificationMeta(
    'limitPaise',
  );
  @override
  late final GeneratedColumn<int> limitPaise = GeneratedColumn<int>(
    'limit_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BudgetPeriod, int> period =
      GeneratedColumn<int>(
        'period',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<BudgetPeriod>($BudgetsTable.$converterperiod);
  @override
  late final GeneratedColumnWithTypeConverter<BudgetKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<BudgetKind>($BudgetsTable.$converterkind);
  static const VerificationMeta _rolloverMeta = const VerificationMeta(
    'rollover',
  );
  @override
  late final GeneratedColumn<bool> rollover = GeneratedColumn<bool>(
    'rollover',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("rollover" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    categoryId,
    name,
    limitPaise,
    period,
    kind,
    rollover,
    archived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Budget> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('limit_paise')) {
      context.handle(
        _limitPaiseMeta,
        limitPaise.isAcceptableOrUnknown(data['limit_paise']!, _limitPaiseMeta),
      );
    } else if (isInserting) {
      context.missing(_limitPaiseMeta);
    }
    if (data.containsKey('rollover')) {
      context.handle(
        _rolloverMeta,
        rollover.isAcceptableOrUnknown(data['rollover']!, _rolloverMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Budget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Budget(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      limitPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}limit_paise'],
      )!,
      period: $BudgetsTable.$converterperiod.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}period'],
        )!,
      ),
      kind: $BudgetsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      rollover: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}rollover'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
    );
  }

  @override
  $BudgetsTable createAlias(String alias) {
    return $BudgetsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BudgetPeriod, int, int> $converterperiod =
      const EnumIndexConverter<BudgetPeriod>(BudgetPeriod.values);
  static JsonTypeConverter2<BudgetKind, int, int> $converterkind =
      const EnumIndexConverter<BudgetKind>(BudgetKind.values);
}

class Budget extends DataClass implements Insertable<Budget> {
  final int id;

  /// Null = an overall (all-categories) budget.
  final int? categoryId;
  final String name;
  final int limitPaise;
  final BudgetPeriod period;
  final BudgetKind kind;
  final bool rollover;
  final bool archived;
  const Budget({
    required this.id,
    this.categoryId,
    required this.name,
    required this.limitPaise,
    required this.period,
    required this.kind,
    required this.rollover,
    required this.archived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['name'] = Variable<String>(name);
    map['limit_paise'] = Variable<int>(limitPaise);
    {
      map['period'] = Variable<int>(
        $BudgetsTable.$converterperiod.toSql(period),
      );
    }
    {
      map['kind'] = Variable<int>($BudgetsTable.$converterkind.toSql(kind));
    }
    map['rollover'] = Variable<bool>(rollover);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  BudgetsCompanion toCompanion(bool nullToAbsent) {
    return BudgetsCompanion(
      id: Value(id),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      name: Value(name),
      limitPaise: Value(limitPaise),
      period: Value(period),
      kind: Value(kind),
      rollover: Value(rollover),
      archived: Value(archived),
    );
  }

  factory Budget.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Budget(
      id: serializer.fromJson<int>(json['id']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      name: serializer.fromJson<String>(json['name']),
      limitPaise: serializer.fromJson<int>(json['limitPaise']),
      period: $BudgetsTable.$converterperiod.fromJson(
        serializer.fromJson<int>(json['period']),
      ),
      kind: $BudgetsTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      rollover: serializer.fromJson<bool>(json['rollover']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'categoryId': serializer.toJson<int?>(categoryId),
      'name': serializer.toJson<String>(name),
      'limitPaise': serializer.toJson<int>(limitPaise),
      'period': serializer.toJson<int>(
        $BudgetsTable.$converterperiod.toJson(period),
      ),
      'kind': serializer.toJson<int>($BudgetsTable.$converterkind.toJson(kind)),
      'rollover': serializer.toJson<bool>(rollover),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  Budget copyWith({
    int? id,
    Value<int?> categoryId = const Value.absent(),
    String? name,
    int? limitPaise,
    BudgetPeriod? period,
    BudgetKind? kind,
    bool? rollover,
    bool? archived,
  }) => Budget(
    id: id ?? this.id,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    name: name ?? this.name,
    limitPaise: limitPaise ?? this.limitPaise,
    period: period ?? this.period,
    kind: kind ?? this.kind,
    rollover: rollover ?? this.rollover,
    archived: archived ?? this.archived,
  );
  Budget copyWithCompanion(BudgetsCompanion data) {
    return Budget(
      id: data.id.present ? data.id.value : this.id,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      name: data.name.present ? data.name.value : this.name,
      limitPaise: data.limitPaise.present
          ? data.limitPaise.value
          : this.limitPaise,
      period: data.period.present ? data.period.value : this.period,
      kind: data.kind.present ? data.kind.value : this.kind,
      rollover: data.rollover.present ? data.rollover.value : this.rollover,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Budget(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('limitPaise: $limitPaise, ')
          ..write('period: $period, ')
          ..write('kind: $kind, ')
          ..write('rollover: $rollover, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    categoryId,
    name,
    limitPaise,
    period,
    kind,
    rollover,
    archived,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Budget &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.name == this.name &&
          other.limitPaise == this.limitPaise &&
          other.period == this.period &&
          other.kind == this.kind &&
          other.rollover == this.rollover &&
          other.archived == this.archived);
}

class BudgetsCompanion extends UpdateCompanion<Budget> {
  final Value<int> id;
  final Value<int?> categoryId;
  final Value<String> name;
  final Value<int> limitPaise;
  final Value<BudgetPeriod> period;
  final Value<BudgetKind> kind;
  final Value<bool> rollover;
  final Value<bool> archived;
  const BudgetsCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.name = const Value.absent(),
    this.limitPaise = const Value.absent(),
    this.period = const Value.absent(),
    this.kind = const Value.absent(),
    this.rollover = const Value.absent(),
    this.archived = const Value.absent(),
  });
  BudgetsCompanion.insert({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    required String name,
    required int limitPaise,
    required BudgetPeriod period,
    required BudgetKind kind,
    this.rollover = const Value.absent(),
    this.archived = const Value.absent(),
  }) : name = Value(name),
       limitPaise = Value(limitPaise),
       period = Value(period),
       kind = Value(kind);
  static Insertable<Budget> custom({
    Expression<int>? id,
    Expression<int>? categoryId,
    Expression<String>? name,
    Expression<int>? limitPaise,
    Expression<int>? period,
    Expression<int>? kind,
    Expression<bool>? rollover,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (name != null) 'name': name,
      if (limitPaise != null) 'limit_paise': limitPaise,
      if (period != null) 'period': period,
      if (kind != null) 'kind': kind,
      if (rollover != null) 'rollover': rollover,
      if (archived != null) 'archived': archived,
    });
  }

  BudgetsCompanion copyWith({
    Value<int>? id,
    Value<int?>? categoryId,
    Value<String>? name,
    Value<int>? limitPaise,
    Value<BudgetPeriod>? period,
    Value<BudgetKind>? kind,
    Value<bool>? rollover,
    Value<bool>? archived,
  }) {
    return BudgetsCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      limitPaise: limitPaise ?? this.limitPaise,
      period: period ?? this.period,
      kind: kind ?? this.kind,
      rollover: rollover ?? this.rollover,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (limitPaise.present) {
      map['limit_paise'] = Variable<int>(limitPaise.value);
    }
    if (period.present) {
      map['period'] = Variable<int>(
        $BudgetsTable.$converterperiod.toSql(period.value),
      );
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $BudgetsTable.$converterkind.toSql(kind.value),
      );
    }
    if (rollover.present) {
      map['rollover'] = Variable<bool>(rollover.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('limitPaise: $limitPaise, ')
          ..write('period: $period, ')
          ..write('kind: $kind, ')
          ..write('rollover: $rollover, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $PinnedsTable extends Pinneds with TableInfo<$PinnedsTable, Pinned> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PinnedsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    amountPaise,
    categoryId,
    accountId,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pinneds';
  @override
  VerificationContext validateIntegrity(
    Insertable<Pinned> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Pinned map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Pinned(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}account_id'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $PinnedsTable createAlias(String alias) {
    return $PinnedsTable(attachedDatabase, alias);
  }
}

class Pinned extends DataClass implements Insertable<Pinned> {
  final int id;
  final String title;
  final int amountPaise;
  final int categoryId;
  final int accountId;
  final int sortOrder;
  const Pinned({
    required this.id,
    required this.title,
    required this.amountPaise,
    required this.categoryId,
    required this.accountId,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['category_id'] = Variable<int>(categoryId);
    map['account_id'] = Variable<int>(accountId);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  PinnedsCompanion toCompanion(bool nullToAbsent) {
    return PinnedsCompanion(
      id: Value(id),
      title: Value(title),
      amountPaise: Value(amountPaise),
      categoryId: Value(categoryId),
      accountId: Value(accountId),
      sortOrder: Value(sortOrder),
    );
  }

  factory Pinned.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Pinned(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      categoryId: serializer.fromJson<int>(json['categoryId']),
      accountId: serializer.fromJson<int>(json['accountId']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'categoryId': serializer.toJson<int>(categoryId),
      'accountId': serializer.toJson<int>(accountId),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Pinned copyWith({
    int? id,
    String? title,
    int? amountPaise,
    int? categoryId,
    int? accountId,
    int? sortOrder,
  }) => Pinned(
    id: id ?? this.id,
    title: title ?? this.title,
    amountPaise: amountPaise ?? this.amountPaise,
    categoryId: categoryId ?? this.categoryId,
    accountId: accountId ?? this.accountId,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Pinned copyWithCompanion(PinnedsCompanion data) {
    return Pinned(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Pinned(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, amountPaise, categoryId, accountId, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Pinned &&
          other.id == this.id &&
          other.title == this.title &&
          other.amountPaise == this.amountPaise &&
          other.categoryId == this.categoryId &&
          other.accountId == this.accountId &&
          other.sortOrder == this.sortOrder);
}

class PinnedsCompanion extends UpdateCompanion<Pinned> {
  final Value<int> id;
  final Value<String> title;
  final Value<int> amountPaise;
  final Value<int> categoryId;
  final Value<int> accountId;
  final Value<int> sortOrder;
  const PinnedsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  PinnedsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required int amountPaise,
    required int categoryId,
    required int accountId,
    this.sortOrder = const Value.absent(),
  }) : title = Value(title),
       amountPaise = Value(amountPaise),
       categoryId = Value(categoryId),
       accountId = Value(accountId);
  static Insertable<Pinned> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<int>? amountPaise,
    Expression<int>? categoryId,
    Expression<int>? accountId,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (categoryId != null) 'category_id': categoryId,
      if (accountId != null) 'account_id': accountId,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  PinnedsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<int>? amountPaise,
    Value<int>? categoryId,
    Value<int>? accountId,
    Value<int>? sortOrder,
  }) {
    return PinnedsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      amountPaise: amountPaise ?? this.amountPaise,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PinnedsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $DaySealsTable extends DaySeals with TableInfo<$DaySealsTable, DaySeal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DaySealsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sealedAtMeta = const VerificationMeta(
    'sealedAt',
  );
  @override
  late final GeneratedColumn<DateTime> sealedAt = GeneratedColumn<DateTime>(
    'sealed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [date, sealedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_seals';
  @override
  VerificationContext validateIntegrity(
    Insertable<DaySeal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('sealed_at')) {
      context.handle(
        _sealedAtMeta,
        sealedAt.isAcceptableOrUnknown(data['sealed_at']!, _sealedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  DaySeal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DaySeal(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      sealedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sealed_at'],
      )!,
    );
  }

  @override
  $DaySealsTable createAlias(String alias) {
    return $DaySealsTable(attachedDatabase, alias);
  }
}

class DaySeal extends DataClass implements Insertable<DaySeal> {
  final String date;
  final DateTime sealedAt;
  const DaySeal({required this.date, required this.sealedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['sealed_at'] = Variable<DateTime>(sealedAt);
    return map;
  }

  DaySealsCompanion toCompanion(bool nullToAbsent) {
    return DaySealsCompanion(date: Value(date), sealedAt: Value(sealedAt));
  }

  factory DaySeal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DaySeal(
      date: serializer.fromJson<String>(json['date']),
      sealedAt: serializer.fromJson<DateTime>(json['sealedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'sealedAt': serializer.toJson<DateTime>(sealedAt),
    };
  }

  DaySeal copyWith({String? date, DateTime? sealedAt}) =>
      DaySeal(date: date ?? this.date, sealedAt: sealedAt ?? this.sealedAt);
  DaySeal copyWithCompanion(DaySealsCompanion data) {
    return DaySeal(
      date: data.date.present ? data.date.value : this.date,
      sealedAt: data.sealedAt.present ? data.sealedAt.value : this.sealedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DaySeal(')
          ..write('date: $date, ')
          ..write('sealedAt: $sealedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(date, sealedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DaySeal &&
          other.date == this.date &&
          other.sealedAt == this.sealedAt);
}

class DaySealsCompanion extends UpdateCompanion<DaySeal> {
  final Value<String> date;
  final Value<DateTime> sealedAt;
  final Value<int> rowid;
  const DaySealsCompanion({
    this.date = const Value.absent(),
    this.sealedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DaySealsCompanion.insert({
    required String date,
    this.sealedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date);
  static Insertable<DaySeal> custom({
    Expression<String>? date,
    Expression<DateTime>? sealedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (sealedAt != null) 'sealed_at': sealedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DaySealsCompanion copyWith({
    Value<String>? date,
    Value<DateTime>? sealedAt,
    Value<int>? rowid,
  }) {
    return DaySealsCompanion(
      date: date ?? this.date,
      sealedAt: sealedAt ?? this.sealedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (sealedAt.present) {
      map['sealed_at'] = Variable<DateTime>(sealedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DaySealsCompanion(')
          ..write('date: $date, ')
          ..write('sealedAt: $sealedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivitiesTable extends Activities
    with TableInfo<$ActivitiesTable, Activity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _txnIdMeta = const VerificationMeta('txnId');
  @override
  late final GeneratedColumn<int> txnId = GeneratedColumn<int>(
    'txn_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ActivityAction, int> action =
      GeneratedColumn<int>(
        'action',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<ActivityAction>($ActivitiesTable.$converteraction);
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, txnId, action, snapshot, at];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<Activity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('txn_id')) {
      context.handle(
        _txnIdMeta,
        txnId.isAcceptableOrUnknown(data['txn_id']!, _txnIdMeta),
      );
    } else if (isInserting) {
      context.missing(_txnIdMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Activity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Activity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      txnId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}txn_id'],
      )!,
      action: $ActivitiesTable.$converteraction.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}action'],
        )!,
      ),
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
    );
  }

  @override
  $ActivitiesTable createAlias(String alias) {
    return $ActivitiesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ActivityAction, int, int> $converteraction =
      const EnumIndexConverter<ActivityAction>(ActivityAction.values);
}

class Activity extends DataClass implements Insertable<Activity> {
  final int id;
  final int txnId;
  final ActivityAction action;

  /// JSON snapshot of the row before/after, enough to undo.
  final String snapshot;
  final DateTime at;
  const Activity({
    required this.id,
    required this.txnId,
    required this.action,
    required this.snapshot,
    required this.at,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['txn_id'] = Variable<int>(txnId);
    {
      map['action'] = Variable<int>(
        $ActivitiesTable.$converteraction.toSql(action),
      );
    }
    map['snapshot'] = Variable<String>(snapshot);
    map['at'] = Variable<DateTime>(at);
    return map;
  }

  ActivitiesCompanion toCompanion(bool nullToAbsent) {
    return ActivitiesCompanion(
      id: Value(id),
      txnId: Value(txnId),
      action: Value(action),
      snapshot: Value(snapshot),
      at: Value(at),
    );
  }

  factory Activity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Activity(
      id: serializer.fromJson<int>(json['id']),
      txnId: serializer.fromJson<int>(json['txnId']),
      action: $ActivitiesTable.$converteraction.fromJson(
        serializer.fromJson<int>(json['action']),
      ),
      snapshot: serializer.fromJson<String>(json['snapshot']),
      at: serializer.fromJson<DateTime>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'txnId': serializer.toJson<int>(txnId),
      'action': serializer.toJson<int>(
        $ActivitiesTable.$converteraction.toJson(action),
      ),
      'snapshot': serializer.toJson<String>(snapshot),
      'at': serializer.toJson<DateTime>(at),
    };
  }

  Activity copyWith({
    int? id,
    int? txnId,
    ActivityAction? action,
    String? snapshot,
    DateTime? at,
  }) => Activity(
    id: id ?? this.id,
    txnId: txnId ?? this.txnId,
    action: action ?? this.action,
    snapshot: snapshot ?? this.snapshot,
    at: at ?? this.at,
  );
  Activity copyWithCompanion(ActivitiesCompanion data) {
    return Activity(
      id: data.id.present ? data.id.value : this.id,
      txnId: data.txnId.present ? data.txnId.value : this.txnId,
      action: data.action.present ? data.action.value : this.action,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Activity(')
          ..write('id: $id, ')
          ..write('txnId: $txnId, ')
          ..write('action: $action, ')
          ..write('snapshot: $snapshot, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, txnId, action, snapshot, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Activity &&
          other.id == this.id &&
          other.txnId == this.txnId &&
          other.action == this.action &&
          other.snapshot == this.snapshot &&
          other.at == this.at);
}

class ActivitiesCompanion extends UpdateCompanion<Activity> {
  final Value<int> id;
  final Value<int> txnId;
  final Value<ActivityAction> action;
  final Value<String> snapshot;
  final Value<DateTime> at;
  const ActivitiesCompanion({
    this.id = const Value.absent(),
    this.txnId = const Value.absent(),
    this.action = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.at = const Value.absent(),
  });
  ActivitiesCompanion.insert({
    this.id = const Value.absent(),
    required int txnId,
    required ActivityAction action,
    required String snapshot,
    this.at = const Value.absent(),
  }) : txnId = Value(txnId),
       action = Value(action),
       snapshot = Value(snapshot);
  static Insertable<Activity> custom({
    Expression<int>? id,
    Expression<int>? txnId,
    Expression<int>? action,
    Expression<String>? snapshot,
    Expression<DateTime>? at,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (txnId != null) 'txn_id': txnId,
      if (action != null) 'action': action,
      if (snapshot != null) 'snapshot': snapshot,
      if (at != null) 'at': at,
    });
  }

  ActivitiesCompanion copyWith({
    Value<int>? id,
    Value<int>? txnId,
    Value<ActivityAction>? action,
    Value<String>? snapshot,
    Value<DateTime>? at,
  }) {
    return ActivitiesCompanion(
      id: id ?? this.id,
      txnId: txnId ?? this.txnId,
      action: action ?? this.action,
      snapshot: snapshot ?? this.snapshot,
      at: at ?? this.at,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (txnId.present) {
      map['txn_id'] = Variable<int>(txnId.value);
    }
    if (action.present) {
      map['action'] = Variable<int>(
        $ActivitiesTable.$converteraction.toSql(action.value),
      );
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivitiesCompanion(')
          ..write('id: $id, ')
          ..write('txnId: $txnId, ')
          ..write('action: $action, ')
          ..write('snapshot: $snapshot, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, Note> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    body,
    pinned,
    createdAt,
    updatedAt,
    archived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Note> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Note(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class Note extends DataClass implements Insertable<Note> {
  final int id;
  final String title;
  final String body;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool archived;
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    required this.archived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['pinned'] = Variable<bool>(pinned);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      title: Value(title),
      body: Value(body),
      pinned: Value(pinned),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      archived: Value(archived),
    );
  }

  factory Note.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'pinned': serializer.toJson<bool>(pinned),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  Note copyWith({
    int? id,
    String? title,
    String? body,
    bool? pinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? archived,
  }) => Note(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archived: archived ?? this.archived,
  );
  Note copyWithCompanion(NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('pinned: $pinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, body, pinned, createdAt, updatedAt, archived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Note &&
          other.id == this.id &&
          other.title == this.title &&
          other.body == this.body &&
          other.pinned == this.pinned &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.archived == this.archived);
}

class NotesCompanion extends UpdateCompanion<Note> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> body;
  final Value<bool> pinned;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> archived;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.pinned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archived = const Value.absent(),
  });
  NotesCompanion.insert({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.pinned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archived = const Value.absent(),
  });
  static Insertable<Note> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? body,
    Expression<bool>? pinned,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (pinned != null) 'pinned': pinned,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archived != null) 'archived': archived,
    });
  }

  NotesCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? body,
    Value<bool>? pinned,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? archived,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('pinned: $pinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $FocusSessionsTable extends FocusSessions
    with TableInfo<$FocusSessionsTable, FocusSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minutesMeta = const VerificationMeta(
    'minutes',
  );
  @override
  late final GeneratedColumn<int> minutes = GeneratedColumn<int>(
    'minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<FocusKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<FocusKind>($FocusSessionsTable.$converterkind);
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    startedAt,
    minutes,
    kind,
    completed,
    label,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('minutes')) {
      context.handle(
        _minutesMeta,
        minutes.isAcceptableOrUnknown(data['minutes']!, _minutesMeta),
      );
    } else if (isInserting) {
      context.missing(_minutesMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FocusSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      minutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minutes'],
      )!,
      kind: $FocusSessionsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
    );
  }

  @override
  $FocusSessionsTable createAlias(String alias) {
    return $FocusSessionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<FocusKind, int, int> $converterkind =
      const EnumIndexConverter<FocusKind>(FocusKind.values);
}

class FocusSession extends DataClass implements Insertable<FocusSession> {
  final int id;
  final DateTime startedAt;
  final int minutes;
  final FocusKind kind;
  final bool completed;
  final String? label;
  const FocusSession({
    required this.id,
    required this.startedAt,
    required this.minutes,
    required this.kind,
    required this.completed,
    this.label,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['minutes'] = Variable<int>(minutes);
    {
      map['kind'] = Variable<int>(
        $FocusSessionsTable.$converterkind.toSql(kind),
      );
    }
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    return map;
  }

  FocusSessionsCompanion toCompanion(bool nullToAbsent) {
    return FocusSessionsCompanion(
      id: Value(id),
      startedAt: Value(startedAt),
      minutes: Value(minutes),
      kind: Value(kind),
      completed: Value(completed),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
    );
  }

  factory FocusSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusSession(
      id: serializer.fromJson<int>(json['id']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      minutes: serializer.fromJson<int>(json['minutes']),
      kind: $FocusSessionsTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      completed: serializer.fromJson<bool>(json['completed']),
      label: serializer.fromJson<String?>(json['label']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'minutes': serializer.toJson<int>(minutes),
      'kind': serializer.toJson<int>(
        $FocusSessionsTable.$converterkind.toJson(kind),
      ),
      'completed': serializer.toJson<bool>(completed),
      'label': serializer.toJson<String?>(label),
    };
  }

  FocusSession copyWith({
    int? id,
    DateTime? startedAt,
    int? minutes,
    FocusKind? kind,
    bool? completed,
    Value<String?> label = const Value.absent(),
  }) => FocusSession(
    id: id ?? this.id,
    startedAt: startedAt ?? this.startedAt,
    minutes: minutes ?? this.minutes,
    kind: kind ?? this.kind,
    completed: completed ?? this.completed,
    label: label.present ? label.value : this.label,
  );
  FocusSession copyWithCompanion(FocusSessionsCompanion data) {
    return FocusSession(
      id: data.id.present ? data.id.value : this.id,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      minutes: data.minutes.present ? data.minutes.value : this.minutes,
      kind: data.kind.present ? data.kind.value : this.kind,
      completed: data.completed.present ? data.completed.value : this.completed,
      label: data.label.present ? data.label.value : this.label,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusSession(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('minutes: $minutes, ')
          ..write('kind: $kind, ')
          ..write('completed: $completed, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, startedAt, minutes, kind, completed, label);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusSession &&
          other.id == this.id &&
          other.startedAt == this.startedAt &&
          other.minutes == this.minutes &&
          other.kind == this.kind &&
          other.completed == this.completed &&
          other.label == this.label);
}

class FocusSessionsCompanion extends UpdateCompanion<FocusSession> {
  final Value<int> id;
  final Value<DateTime> startedAt;
  final Value<int> minutes;
  final Value<FocusKind> kind;
  final Value<bool> completed;
  final Value<String?> label;
  const FocusSessionsCompanion({
    this.id = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.minutes = const Value.absent(),
    this.kind = const Value.absent(),
    this.completed = const Value.absent(),
    this.label = const Value.absent(),
  });
  FocusSessionsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime startedAt,
    required int minutes,
    required FocusKind kind,
    this.completed = const Value.absent(),
    this.label = const Value.absent(),
  }) : startedAt = Value(startedAt),
       minutes = Value(minutes),
       kind = Value(kind);
  static Insertable<FocusSession> custom({
    Expression<int>? id,
    Expression<DateTime>? startedAt,
    Expression<int>? minutes,
    Expression<int>? kind,
    Expression<bool>? completed,
    Expression<String>? label,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedAt != null) 'started_at': startedAt,
      if (minutes != null) 'minutes': minutes,
      if (kind != null) 'kind': kind,
      if (completed != null) 'completed': completed,
      if (label != null) 'label': label,
    });
  }

  FocusSessionsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? startedAt,
    Value<int>? minutes,
    Value<FocusKind>? kind,
    Value<bool>? completed,
    Value<String?>? label,
  }) {
    return FocusSessionsCompanion(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      minutes: minutes ?? this.minutes,
      kind: kind ?? this.kind,
      completed: completed ?? this.completed,
      label: label ?? this.label,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (minutes.present) {
      map['minutes'] = Variable<int>(minutes.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $FocusSessionsTable.$converterkind.toSql(kind.value),
      );
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusSessionsCompanion(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('minutes: $minutes, ')
          ..write('kind: $kind, ')
          ..write('completed: $completed, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }
}

class $JournalEntriesTable extends JournalEntries
    with TableInfo<$JournalEntriesTable, JournalEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<int> mood = GeneratedColumn<int>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [date, body, mood, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  JournalEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalEntry(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mood'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $JournalEntriesTable createAlias(String alias) {
    return $JournalEntriesTable(attachedDatabase, alias);
  }
}

class JournalEntry extends DataClass implements Insertable<JournalEntry> {
  /// One page per day: 'yyyy-MM-dd'.
  final String date;
  final String body;

  /// 1 (rough) … 5 (great); null when unrecorded.
  final int? mood;
  final DateTime updatedAt;
  const JournalEntry({
    required this.date,
    required this.body,
    this.mood,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<int>(mood);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  JournalEntriesCompanion toCompanion(bool nullToAbsent) {
    return JournalEntriesCompanion(
      date: Value(date),
      body: Value(body),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      updatedAt: Value(updatedAt),
    );
  }

  factory JournalEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalEntry(
      date: serializer.fromJson<String>(json['date']),
      body: serializer.fromJson<String>(json['body']),
      mood: serializer.fromJson<int?>(json['mood']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'body': serializer.toJson<String>(body),
      'mood': serializer.toJson<int?>(mood),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  JournalEntry copyWith({
    String? date,
    String? body,
    Value<int?> mood = const Value.absent(),
    DateTime? updatedAt,
  }) => JournalEntry(
    date: date ?? this.date,
    body: body ?? this.body,
    mood: mood.present ? mood.value : this.mood,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  JournalEntry copyWithCompanion(JournalEntriesCompanion data) {
    return JournalEntry(
      date: data.date.present ? data.date.value : this.date,
      body: data.body.present ? data.body.value : this.body,
      mood: data.mood.present ? data.mood.value : this.mood,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntry(')
          ..write('date: $date, ')
          ..write('body: $body, ')
          ..write('mood: $mood, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(date, body, mood, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalEntry &&
          other.date == this.date &&
          other.body == this.body &&
          other.mood == this.mood &&
          other.updatedAt == this.updatedAt);
}

class JournalEntriesCompanion extends UpdateCompanion<JournalEntry> {
  final Value<String> date;
  final Value<String> body;
  final Value<int?> mood;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const JournalEntriesCompanion({
    this.date = const Value.absent(),
    this.body = const Value.absent(),
    this.mood = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalEntriesCompanion.insert({
    required String date,
    this.body = const Value.absent(),
    this.mood = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date);
  static Insertable<JournalEntry> custom({
    Expression<String>? date,
    Expression<String>? body,
    Expression<int>? mood,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (body != null) 'body': body,
      if (mood != null) 'mood': mood,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JournalEntriesCompanion copyWith({
    Value<String>? date,
    Value<String>? body,
    Value<int?>? mood,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return JournalEntriesCompanion(
      date: date ?? this.date,
      body: body ?? this.body,
      mood: mood ?? this.mood,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (mood.present) {
      map['mood'] = Variable<int>(mood.value);
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
    return (StringBuffer('JournalEntriesCompanion(')
          ..write('date: $date, ')
          ..write('body: $body, ')
          ..write('mood: $mood, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeMinutesMeta = const VerificationMeta(
    'timeMinutes',
  );
  @override
  late final GeneratedColumn<int> timeMinutes = GeneratedColumn<int>(
    'time_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EventRepeat, int> repeat =
      GeneratedColumn<int>(
        'repeat',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: Constant(EventRepeat.none.index),
      ).withConverter<EventRepeat>($EventsTable.$converterrepeat);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    note,
    date,
    timeMinutes,
    repeat,
    createdAt,
    archived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('time_minutes')) {
      context.handle(
        _timeMinutesMeta,
        timeMinutes.isAcceptableOrUnknown(
          data['time_minutes']!,
          _timeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      timeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_minutes'],
      ),
      repeat: $EventsTable.$converterrepeat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}repeat'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EventRepeat, int, int> $converterrepeat =
      const EnumIndexConverter<EventRepeat>(EventRepeat.values);
}

class Event extends DataClass implements Insertable<Event> {
  final int id;
  final String title;
  final String? note;

  /// Anchor date 'yyyy-MM-dd'; a yearly repeat recurs on this month+day.
  final String date;

  /// Minutes past midnight; null = all-day.
  final int? timeMinutes;
  final EventRepeat repeat;
  final DateTime createdAt;
  final bool archived;
  const Event({
    required this.id,
    required this.title,
    this.note,
    required this.date,
    this.timeMinutes,
    required this.repeat,
    required this.createdAt,
    required this.archived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['date'] = Variable<String>(date);
    if (!nullToAbsent || timeMinutes != null) {
      map['time_minutes'] = Variable<int>(timeMinutes);
    }
    {
      map['repeat'] = Variable<int>(
        $EventsTable.$converterrepeat.toSql(repeat),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      title: Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      date: Value(date),
      timeMinutes: timeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(timeMinutes),
      repeat: Value(repeat),
      createdAt: Value(createdAt),
      archived: Value(archived),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      date: serializer.fromJson<String>(json['date']),
      timeMinutes: serializer.fromJson<int?>(json['timeMinutes']),
      repeat: $EventsTable.$converterrepeat.fromJson(
        serializer.fromJson<int>(json['repeat']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'note': serializer.toJson<String?>(note),
      'date': serializer.toJson<String>(date),
      'timeMinutes': serializer.toJson<int?>(timeMinutes),
      'repeat': serializer.toJson<int>(
        $EventsTable.$converterrepeat.toJson(repeat),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  Event copyWith({
    int? id,
    String? title,
    Value<String?> note = const Value.absent(),
    String? date,
    Value<int?> timeMinutes = const Value.absent(),
    EventRepeat? repeat,
    DateTime? createdAt,
    bool? archived,
  }) => Event(
    id: id ?? this.id,
    title: title ?? this.title,
    note: note.present ? note.value : this.note,
    date: date ?? this.date,
    timeMinutes: timeMinutes.present ? timeMinutes.value : this.timeMinutes,
    repeat: repeat ?? this.repeat,
    createdAt: createdAt ?? this.createdAt,
    archived: archived ?? this.archived,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      date: data.date.present ? data.date.value : this.date,
      timeMinutes: data.timeMinutes.present
          ? data.timeMinutes.value
          : this.timeMinutes,
      repeat: data.repeat.present ? data.repeat.value : this.repeat,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('date: $date, ')
          ..write('timeMinutes: $timeMinutes, ')
          ..write('repeat: $repeat, ')
          ..write('createdAt: $createdAt, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    note,
    date,
    timeMinutes,
    repeat,
    createdAt,
    archived,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == this.id &&
          other.title == this.title &&
          other.note == this.note &&
          other.date == this.date &&
          other.timeMinutes == this.timeMinutes &&
          other.repeat == this.repeat &&
          other.createdAt == this.createdAt &&
          other.archived == this.archived);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<int> id;
  final Value<String> title;
  final Value<String?> note;
  final Value<String> date;
  final Value<int?> timeMinutes;
  final Value<EventRepeat> repeat;
  final Value<DateTime> createdAt;
  final Value<bool> archived;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.date = const Value.absent(),
    this.timeMinutes = const Value.absent(),
    this.repeat = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.archived = const Value.absent(),
  });
  EventsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.note = const Value.absent(),
    required String date,
    this.timeMinutes = const Value.absent(),
    this.repeat = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.archived = const Value.absent(),
  }) : title = Value(title),
       date = Value(date);
  static Insertable<Event> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? note,
    Expression<String>? date,
    Expression<int>? timeMinutes,
    Expression<int>? repeat,
    Expression<DateTime>? createdAt,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (date != null) 'date': date,
      if (timeMinutes != null) 'time_minutes': timeMinutes,
      if (repeat != null) 'repeat': repeat,
      if (createdAt != null) 'created_at': createdAt,
      if (archived != null) 'archived': archived,
    });
  }

  EventsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String?>? note,
    Value<String>? date,
    Value<int?>? timeMinutes,
    Value<EventRepeat>? repeat,
    Value<DateTime>? createdAt,
    Value<bool>? archived,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      date: date ?? this.date,
      timeMinutes: timeMinutes ?? this.timeMinutes,
      repeat: repeat ?? this.repeat,
      createdAt: createdAt ?? this.createdAt,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (timeMinutes.present) {
      map['time_minutes'] = Variable<int>(timeMinutes.value);
    }
    if (repeat.present) {
      map['repeat'] = Variable<int>(
        $EventsTable.$converterrepeat.toSql(repeat.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('date: $date, ')
          ..write('timeMinutes: $timeMinutes, ')
          ..write('repeat: $repeat, ')
          ..write('createdAt: $createdAt, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $VaultItemsTable extends VaultItems
    with TableInfo<$VaultItemsTable, VaultItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VaultItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<String> nonce = GeneratedColumn<String>(
    'nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cipherMeta = const VerificationMeta('cipher');
  @override
  late final GeneratedColumn<String> cipher = GeneratedColumn<String>(
    'cipher',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nonce,
    cipher,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vault_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('nonce')) {
      context.handle(
        _nonceMeta,
        nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta),
      );
    } else if (isInserting) {
      context.missing(_nonceMeta);
    }
    if (data.containsKey('cipher')) {
      context.handle(
        _cipherMeta,
        cipher.isAcceptableOrUnknown(data['cipher']!, _cipherMeta),
      );
    } else if (isInserting) {
      context.missing(_cipherMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      nonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nonce'],
      )!,
      cipher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cipher'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $VaultItemsTable createAlias(String alias) {
    return $VaultItemsTable(attachedDatabase, alias);
  }
}

class VaultItem extends DataClass implements Insertable<VaultItem> {
  final int id;
  final String nonce;
  final String cipher;
  final DateTime createdAt;
  final DateTime updatedAt;
  const VaultItem({
    required this.id,
    required this.nonce,
    required this.cipher,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['nonce'] = Variable<String>(nonce);
    map['cipher'] = Variable<String>(cipher);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  VaultItemsCompanion toCompanion(bool nullToAbsent) {
    return VaultItemsCompanion(
      id: Value(id),
      nonce: Value(nonce),
      cipher: Value(cipher),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory VaultItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultItem(
      id: serializer.fromJson<int>(json['id']),
      nonce: serializer.fromJson<String>(json['nonce']),
      cipher: serializer.fromJson<String>(json['cipher']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'nonce': serializer.toJson<String>(nonce),
      'cipher': serializer.toJson<String>(cipher),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  VaultItem copyWith({
    int? id,
    String? nonce,
    String? cipher,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => VaultItem(
    id: id ?? this.id,
    nonce: nonce ?? this.nonce,
    cipher: cipher ?? this.cipher,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  VaultItem copyWithCompanion(VaultItemsCompanion data) {
    return VaultItem(
      id: data.id.present ? data.id.value : this.id,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      cipher: data.cipher.present ? data.cipher.value : this.cipher,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultItem(')
          ..write('id: $id, ')
          ..write('nonce: $nonce, ')
          ..write('cipher: $cipher, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, nonce, cipher, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultItem &&
          other.id == this.id &&
          other.nonce == this.nonce &&
          other.cipher == this.cipher &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class VaultItemsCompanion extends UpdateCompanion<VaultItem> {
  final Value<int> id;
  final Value<String> nonce;
  final Value<String> cipher;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const VaultItemsCompanion({
    this.id = const Value.absent(),
    this.nonce = const Value.absent(),
    this.cipher = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  VaultItemsCompanion.insert({
    this.id = const Value.absent(),
    required String nonce,
    required String cipher,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : nonce = Value(nonce),
       cipher = Value(cipher);
  static Insertable<VaultItem> custom({
    Expression<int>? id,
    Expression<String>? nonce,
    Expression<String>? cipher,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nonce != null) 'nonce': nonce,
      if (cipher != null) 'cipher': cipher,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  VaultItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? nonce,
    Value<String>? cipher,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return VaultItemsCompanion(
      id: id ?? this.id,
      nonce: nonce ?? this.nonce,
      cipher: cipher ?? this.cipher,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<String>(nonce.value);
    }
    if (cipher.present) {
      map['cipher'] = Variable<String>(cipher.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VaultItemsCompanion(')
          ..write('id: $id, ')
          ..write('nonce: $nonce, ')
          ..write('cipher: $cipher, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $BalanceSnapshotsTable extends BalanceSnapshots
    with TableInfo<$BalanceSnapshotsTable, BalanceSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BalanceSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _balancePaiseMeta = const VerificationMeta(
    'balancePaise',
  );
  @override
  late final GeneratedColumn<int> balancePaise = GeneratedColumn<int>(
    'balance_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, date, balancePaise];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'balance_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<BalanceSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('balance_paise')) {
      context.handle(
        _balancePaiseMeta,
        balancePaise.isAcceptableOrUnknown(
          data['balance_paise']!,
          _balancePaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_balancePaiseMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, date};
  @override
  BalanceSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BalanceSnapshot(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}account_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      balancePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balance_paise'],
      )!,
    );
  }

  @override
  $BalanceSnapshotsTable createAlias(String alias) {
    return $BalanceSnapshotsTable(attachedDatabase, alias);
  }
}

class BalanceSnapshot extends DataClass implements Insertable<BalanceSnapshot> {
  final int accountId;
  final String date;
  final int balancePaise;
  const BalanceSnapshot({
    required this.accountId,
    required this.date,
    required this.balancePaise,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<int>(accountId);
    map['date'] = Variable<String>(date);
    map['balance_paise'] = Variable<int>(balancePaise);
    return map;
  }

  BalanceSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return BalanceSnapshotsCompanion(
      accountId: Value(accountId),
      date: Value(date),
      balancePaise: Value(balancePaise),
    );
  }

  factory BalanceSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BalanceSnapshot(
      accountId: serializer.fromJson<int>(json['accountId']),
      date: serializer.fromJson<String>(json['date']),
      balancePaise: serializer.fromJson<int>(json['balancePaise']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<int>(accountId),
      'date': serializer.toJson<String>(date),
      'balancePaise': serializer.toJson<int>(balancePaise),
    };
  }

  BalanceSnapshot copyWith({int? accountId, String? date, int? balancePaise}) =>
      BalanceSnapshot(
        accountId: accountId ?? this.accountId,
        date: date ?? this.date,
        balancePaise: balancePaise ?? this.balancePaise,
      );
  BalanceSnapshot copyWithCompanion(BalanceSnapshotsCompanion data) {
    return BalanceSnapshot(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      date: data.date.present ? data.date.value : this.date,
      balancePaise: data.balancePaise.present
          ? data.balancePaise.value
          : this.balancePaise,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BalanceSnapshot(')
          ..write('accountId: $accountId, ')
          ..write('date: $date, ')
          ..write('balancePaise: $balancePaise')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, date, balancePaise);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BalanceSnapshot &&
          other.accountId == this.accountId &&
          other.date == this.date &&
          other.balancePaise == this.balancePaise);
}

class BalanceSnapshotsCompanion extends UpdateCompanion<BalanceSnapshot> {
  final Value<int> accountId;
  final Value<String> date;
  final Value<int> balancePaise;
  final Value<int> rowid;
  const BalanceSnapshotsCompanion({
    this.accountId = const Value.absent(),
    this.date = const Value.absent(),
    this.balancePaise = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BalanceSnapshotsCompanion.insert({
    required int accountId,
    required String date,
    required int balancePaise,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       date = Value(date),
       balancePaise = Value(balancePaise);
  static Insertable<BalanceSnapshot> custom({
    Expression<int>? accountId,
    Expression<String>? date,
    Expression<int>? balancePaise,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (date != null) 'date': date,
      if (balancePaise != null) 'balance_paise': balancePaise,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BalanceSnapshotsCompanion copyWith({
    Value<int>? accountId,
    Value<String>? date,
    Value<int>? balancePaise,
    Value<int>? rowid,
  }) {
    return BalanceSnapshotsCompanion(
      accountId: accountId ?? this.accountId,
      date: date ?? this.date,
      balancePaise: balancePaise ?? this.balancePaise,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (balancePaise.present) {
      map['balance_paise'] = Variable<int>(balancePaise.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BalanceSnapshotsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('date: $date, ')
          ..write('balancePaise: $balancePaise, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemoteIdsTable extends RemoteIds
    with TableInfo<$RemoteIdsTable, RemoteId> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteIdsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [kind, localId, remoteId, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_ids';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteId> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, localId};
  @override
  RemoteId map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteId(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
    );
  }

  @override
  $RemoteIdsTable createAlias(String alias) {
    return $RemoteIdsTable(attachedDatabase, alias);
  }
}

class RemoteId extends DataClass implements Insertable<RemoteId> {
  final String kind;

  /// The autoincrement id the UI knows this row by.
  final int localId;

  /// The server's uuid7. Minted on the phone when the row is first queued,
  /// so a write can be retried blindly and stay idempotent.
  final String remoteId;

  /// The server's `updated_at` as of the last successful sync — what a pull
  /// compares against to know whether the phone's copy is stale.
  final DateTime? syncedAt;
  const RemoteId({
    required this.kind,
    required this.localId,
    required this.remoteId,
    this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['local_id'] = Variable<int>(localId);
    map['remote_id'] = Variable<String>(remoteId);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  RemoteIdsCompanion toCompanion(bool nullToAbsent) {
    return RemoteIdsCompanion(
      kind: Value(kind),
      localId: Value(localId),
      remoteId: Value(remoteId),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory RemoteId.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteId(
      kind: serializer.fromJson<String>(json['kind']),
      localId: serializer.fromJson<int>(json['localId']),
      remoteId: serializer.fromJson<String>(json['remoteId']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'localId': serializer.toJson<int>(localId),
      'remoteId': serializer.toJson<String>(remoteId),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  RemoteId copyWith({
    String? kind,
    int? localId,
    String? remoteId,
    Value<DateTime?> syncedAt = const Value.absent(),
  }) => RemoteId(
    kind: kind ?? this.kind,
    localId: localId ?? this.localId,
    remoteId: remoteId ?? this.remoteId,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
  );
  RemoteId copyWithCompanion(RemoteIdsCompanion data) {
    return RemoteId(
      kind: data.kind.present ? data.kind.value : this.kind,
      localId: data.localId.present ? data.localId.value : this.localId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteId(')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('remoteId: $remoteId, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, localId, remoteId, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteId &&
          other.kind == this.kind &&
          other.localId == this.localId &&
          other.remoteId == this.remoteId &&
          other.syncedAt == this.syncedAt);
}

class RemoteIdsCompanion extends UpdateCompanion<RemoteId> {
  final Value<String> kind;
  final Value<int> localId;
  final Value<String> remoteId;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const RemoteIdsCompanion({
    this.kind = const Value.absent(),
    this.localId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteIdsCompanion.insert({
    required String kind,
    required int localId,
    required String remoteId,
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       localId = Value(localId),
       remoteId = Value(remoteId);
  static Insertable<RemoteId> custom({
    Expression<String>? kind,
    Expression<int>? localId,
    Expression<String>? remoteId,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (localId != null) 'local_id': localId,
      if (remoteId != null) 'remote_id': remoteId,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteIdsCompanion copyWith({
    Value<String>? kind,
    Value<int>? localId,
    Value<String>? remoteId,
    Value<DateTime?>? syncedAt,
    Value<int>? rowid,
  }) {
    return RemoteIdsCompanion(
      kind: kind ?? this.kind,
      localId: localId ?? this.localId,
      remoteId: remoteId ?? this.remoteId,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteIdsCompanion(')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('remoteId: $remoteId, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<OutboxOp, int> op =
      GeneratedColumn<int>(
        'op',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<OutboxOp>($OutboxTable.$converterop);
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _queuedAtMeta = const VerificationMeta(
    'queuedAt',
  );
  @override
  late final GeneratedColumn<DateTime> queuedAt = GeneratedColumn<DateTime>(
    'queued_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    localId,
    remoteId,
    op,
    payload,
    queuedAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('queued_at')) {
      context.handle(
        _queuedAtMeta,
        queuedAt.isAcceptableOrUnknown(data['queued_at']!, _queuedAtMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      )!,
      op: $OutboxTable.$converterop.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}op'],
        )!,
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      queuedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}queued_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<OutboxOp, int, int> $converterop =
      const EnumIndexConverter<OutboxOp>(OutboxOp.values);
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final int id;
  final String kind;
  final int localId;

  /// The uuid7 this write targets — the idempotency key.
  final String remoteId;
  final OutboxOp op;

  /// The request body as JSON. Null for a delete.
  final String? payload;
  final DateTime queuedAt;

  /// Attempts so far, and why the last one failed — the sync page's evidence
  /// when something is stuck, rather than a silent retry loop.
  final int attempts;
  final String? lastError;
  const OutboxData({
    required this.id,
    required this.kind,
    required this.localId,
    required this.remoteId,
    required this.op,
    this.payload,
    required this.queuedAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['local_id'] = Variable<int>(localId);
    map['remote_id'] = Variable<String>(remoteId);
    {
      map['op'] = Variable<int>($OutboxTable.$converterop.toSql(op));
    }
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    map['queued_at'] = Variable<DateTime>(queuedAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      kind: Value(kind),
      localId: Value(localId),
      remoteId: Value(remoteId),
      op: Value(op),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      queuedAt: Value(queuedAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      localId: serializer.fromJson<int>(json['localId']),
      remoteId: serializer.fromJson<String>(json['remoteId']),
      op: $OutboxTable.$converterop.fromJson(
        serializer.fromJson<int>(json['op']),
      ),
      payload: serializer.fromJson<String?>(json['payload']),
      queuedAt: serializer.fromJson<DateTime>(json['queuedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'localId': serializer.toJson<int>(localId),
      'remoteId': serializer.toJson<String>(remoteId),
      'op': serializer.toJson<int>($OutboxTable.$converterop.toJson(op)),
      'payload': serializer.toJson<String?>(payload),
      'queuedAt': serializer.toJson<DateTime>(queuedAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxData copyWith({
    int? id,
    String? kind,
    int? localId,
    String? remoteId,
    OutboxOp? op,
    Value<String?> payload = const Value.absent(),
    DateTime? queuedAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => OutboxData(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    localId: localId ?? this.localId,
    remoteId: remoteId ?? this.remoteId,
    op: op ?? this.op,
    payload: payload.present ? payload.value : this.payload,
    queuedAt: queuedAt ?? this.queuedAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      localId: data.localId.present ? data.localId.value : this.localId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      op: data.op.present ? data.op.value : this.op,
      payload: data.payload.present ? data.payload.value : this.payload,
      queuedAt: data.queuedAt.present ? data.queuedAt.value : this.queuedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('remoteId: $remoteId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    localId,
    remoteId,
    op,
    payload,
    queuedAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.localId == this.localId &&
          other.remoteId == this.remoteId &&
          other.op == this.op &&
          other.payload == this.payload &&
          other.queuedAt == this.queuedAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<int> id;
  final Value<String> kind;
  final Value<int> localId;
  final Value<String> remoteId;
  final Value<OutboxOp> op;
  final Value<String?> payload;
  final Value<DateTime> queuedAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.localId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.op = const Value.absent(),
    this.payload = const Value.absent(),
    this.queuedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required int localId,
    required String remoteId,
    required OutboxOp op,
    this.payload = const Value.absent(),
    this.queuedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : kind = Value(kind),
       localId = Value(localId),
       remoteId = Value(remoteId),
       op = Value(op);
  static Insertable<OutboxData> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<int>? localId,
    Expression<String>? remoteId,
    Expression<int>? op,
    Expression<String>? payload,
    Expression<DateTime>? queuedAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (localId != null) 'local_id': localId,
      if (remoteId != null) 'remote_id': remoteId,
      if (op != null) 'op': op,
      if (payload != null) 'payload': payload,
      if (queuedAt != null) 'queued_at': queuedAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<int>? localId,
    Value<String>? remoteId,
    Value<OutboxOp>? op,
    Value<String?>? payload,
    Value<DateTime>? queuedAt,
    Value<int>? attempts,
    Value<String?>? lastError,
  }) {
    return OutboxCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      localId: localId ?? this.localId,
      remoteId: remoteId ?? this.remoteId,
      op: op ?? this.op,
      payload: payload ?? this.payload,
      queuedAt: queuedAt ?? this.queuedAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (op.present) {
      map['op'] = Variable<int>($OutboxTable.$converterop.toSql(op.value));
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (queuedAt.present) {
      map['queued_at'] = Variable<DateTime>(queuedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('remoteId: $remoteId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $DayMarksTable extends DayMarks with TableInfo<$DayMarksTable, DayMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayMarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, date, kind, note, at];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<DayMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DayMark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DayMark(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
    );
  }

  @override
  $DayMarksTable createAlias(String alias) {
    return $DayMarksTable(attachedDatabase, alias);
  }
}

class DayMark extends DataClass implements Insertable<DayMark> {
  final int id;
  final String date;
  final String kind;
  final String? note;
  final DateTime at;
  const DayMark({
    required this.id,
    required this.date,
    required this.kind,
    this.note,
    required this.at,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<String>(date);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['at'] = Variable<DateTime>(at);
    return map;
  }

  DayMarksCompanion toCompanion(bool nullToAbsent) {
    return DayMarksCompanion(
      id: Value(id),
      date: Value(date),
      kind: Value(kind),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      at: Value(at),
    );
  }

  factory DayMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DayMark(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      kind: serializer.fromJson<String>(json['kind']),
      note: serializer.fromJson<String?>(json['note']),
      at: serializer.fromJson<DateTime>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<String>(date),
      'kind': serializer.toJson<String>(kind),
      'note': serializer.toJson<String?>(note),
      'at': serializer.toJson<DateTime>(at),
    };
  }

  DayMark copyWith({
    int? id,
    String? date,
    String? kind,
    Value<String?> note = const Value.absent(),
    DateTime? at,
  }) => DayMark(
    id: id ?? this.id,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    note: note.present ? note.value : this.note,
    at: at ?? this.at,
  );
  DayMark copyWithCompanion(DayMarksCompanion data) {
    return DayMark(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      kind: data.kind.present ? data.kind.value : this.kind,
      note: data.note.present ? data.note.value : this.note,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayMark(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('kind: $kind, ')
          ..write('note: $note, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, date, kind, note, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayMark &&
          other.id == this.id &&
          other.date == this.date &&
          other.kind == this.kind &&
          other.note == this.note &&
          other.at == this.at);
}

class DayMarksCompanion extends UpdateCompanion<DayMark> {
  final Value<int> id;
  final Value<String> date;
  final Value<String> kind;
  final Value<String?> note;
  final Value<DateTime> at;
  const DayMarksCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.kind = const Value.absent(),
    this.note = const Value.absent(),
    this.at = const Value.absent(),
  });
  DayMarksCompanion.insert({
    this.id = const Value.absent(),
    required String date,
    required String kind,
    this.note = const Value.absent(),
    this.at = const Value.absent(),
  }) : date = Value(date),
       kind = Value(kind);
  static Insertable<DayMark> custom({
    Expression<int>? id,
    Expression<String>? date,
    Expression<String>? kind,
    Expression<String>? note,
    Expression<DateTime>? at,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (kind != null) 'kind': kind,
      if (note != null) 'note': note,
      if (at != null) 'at': at,
    });
  }

  DayMarksCompanion copyWith({
    Value<int>? id,
    Value<String>? date,
    Value<String>? kind,
    Value<String?>? note,
    Value<DateTime>? at,
  }) {
    return DayMarksCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      kind: kind ?? this.kind,
      note: note ?? this.note,
      at: at ?? this.at,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayMarksCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('kind: $kind, ')
          ..write('note: $note, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }
}

abstract class _$LedgerDb extends GeneratedDatabase {
  _$LedgerDb(QueryExecutor e) : super(e);
  $LedgerDbManager get managers => $LedgerDbManager(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $GoalsTable goals = $GoalsTable(this);
  late final $RecurringsTable recurrings = $RecurringsTable(this);
  late final $TxnsTable txns = $TxnsTable(this);
  late final $BudgetsTable budgets = $BudgetsTable(this);
  late final $PinnedsTable pinneds = $PinnedsTable(this);
  late final $DaySealsTable daySeals = $DaySealsTable(this);
  late final $ActivitiesTable activities = $ActivitiesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $FocusSessionsTable focusSessions = $FocusSessionsTable(this);
  late final $JournalEntriesTable journalEntries = $JournalEntriesTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $VaultItemsTable vaultItems = $VaultItemsTable(this);
  late final $BalanceSnapshotsTable balanceSnapshots = $BalanceSnapshotsTable(
    this,
  );
  late final $RemoteIdsTable remoteIds = $RemoteIdsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $DayMarksTable dayMarks = $DayMarksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accounts,
    categories,
    goals,
    recurrings,
    txns,
    budgets,
    pinneds,
    daySeals,
    activities,
    settings,
    notes,
    focusSessions,
    journalEntries,
    events,
    vaultItems,
    balanceSnapshots,
    remoteIds,
    outbox,
    dayMarks,
  ];
}

typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      Value<int> id,
      required String name,
      required AccountKind kind,
      Value<int> balancePaise,
      Value<DateTime> asOf,
      Value<int> sortOrder,
      Value<bool> archived,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<AccountKind> kind,
      Value<int> balancePaise,
      Value<DateTime> asOf,
      Value<int> sortOrder,
      Value<bool> archived,
    });

final class $$AccountsTableReferences
    extends BaseReferences<_$LedgerDb, $AccountsTable, Account> {
  $$AccountsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RecurringsTable, List<Recurring>>
  _recurringsRefsTable(_$LedgerDb db) => MultiTypedResultKey.fromTable(
    db.recurrings,
    aliasName: 'accounts__id__recurrings__account_id',
  );

  $$RecurringsTableProcessedTableManager get recurringsRefs {
    final manager = $$RecurringsTableTableManager(
      $_db,
      $_db.recurrings,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_recurringsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PinnedsTable, List<Pinned>> _pinnedsRefsTable(
    _$LedgerDb db,
  ) => MultiTypedResultKey.fromTable(
    db.pinneds,
    aliasName: 'accounts__id__pinneds__account_id',
  );

  $$PinnedsTableProcessedTableManager get pinnedsRefs {
    final manager = $$PinnedsTableTableManager(
      $_db,
      $_db.pinneds,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_pinnedsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BalanceSnapshotsTable, List<BalanceSnapshot>>
  _balanceSnapshotsRefsTable(_$LedgerDb db) => MultiTypedResultKey.fromTable(
    db.balanceSnapshots,
    aliasName: 'accounts__id__balance_snapshots__account_id',
  );

  $$BalanceSnapshotsTableProcessedTableManager get balanceSnapshotsRefs {
    final manager = $$BalanceSnapshotsTableTableManager(
      $_db,
      $_db.balanceSnapshots,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _balanceSnapshotsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AccountsTableFilterComposer
    extends Composer<_$LedgerDb, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AccountKind, AccountKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> recurringsRefs(
    Expression<bool> Function($$RecurringsTableFilterComposer f) f,
  ) {
    final $$RecurringsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recurrings,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringsTableFilterComposer(
            $db: $db,
            $table: $db.recurrings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> pinnedsRefs(
    Expression<bool> Function($$PinnedsTableFilterComposer f) f,
  ) {
    final $$PinnedsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pinneds,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PinnedsTableFilterComposer(
            $db: $db,
            $table: $db.pinneds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> balanceSnapshotsRefs(
    Expression<bool> Function($$BalanceSnapshotsTableFilterComposer f) f,
  ) {
    final $$BalanceSnapshotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.balanceSnapshots,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BalanceSnapshotsTableFilterComposer(
            $db: $db,
            $table: $db.balanceSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableOrderingComposer
    extends Composer<_$LedgerDb, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$LedgerDb, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AccountKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get asOf =>
      $composableBuilder(column: $table.asOf, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  Expression<T> recurringsRefs<T extends Object>(
    Expression<T> Function($$RecurringsTableAnnotationComposer a) f,
  ) {
    final $$RecurringsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recurrings,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringsTableAnnotationComposer(
            $db: $db,
            $table: $db.recurrings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> pinnedsRefs<T extends Object>(
    Expression<T> Function($$PinnedsTableAnnotationComposer a) f,
  ) {
    final $$PinnedsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pinneds,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PinnedsTableAnnotationComposer(
            $db: $db,
            $table: $db.pinneds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> balanceSnapshotsRefs<T extends Object>(
    Expression<T> Function($$BalanceSnapshotsTableAnnotationComposer a) f,
  ) {
    final $$BalanceSnapshotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.balanceSnapshots,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BalanceSnapshotsTableAnnotationComposer(
            $db: $db,
            $table: $db.balanceSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, $$AccountsTableReferences),
          Account,
          PrefetchHooks Function({
            bool recurringsRefs,
            bool pinnedsRefs,
            bool balanceSnapshotsRefs,
          })
        > {
  $$AccountsTableTableManager(_$LedgerDb db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<AccountKind> kind = const Value.absent(),
                Value<int> balancePaise = const Value.absent(),
                Value<DateTime> asOf = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                name: name,
                kind: kind,
                balancePaise: balancePaise,
                asOf: asOf,
                sortOrder: sortOrder,
                archived: archived,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required AccountKind kind,
                Value<int> balancePaise = const Value.absent(),
                Value<DateTime> asOf = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                balancePaise: balancePaise,
                asOf: asOf,
                sortOrder: sortOrder,
                archived: archived,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AccountsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                recurringsRefs = false,
                pinnedsRefs = false,
                balanceSnapshotsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (recurringsRefs) db.recurrings,
                    if (pinnedsRefs) db.pinneds,
                    if (balanceSnapshotsRefs) db.balanceSnapshots,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (recurringsRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          Recurring
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._recurringsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).recurringsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (pinnedsRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          Pinned
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._pinnedsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).pinnedsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (balanceSnapshotsRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          BalanceSnapshot
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._balanceSnapshotsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).balanceSnapshotsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, $$AccountsTableReferences),
      Account,
      PrefetchHooks Function({
        bool recurringsRefs,
        bool pinnedsRefs,
        bool balanceSnapshotsRefs,
      })
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      required String name,
      Value<String> icon,
      required CategoryKind kind,
      Value<int> sortOrder,
      Value<bool> archived,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> icon,
      Value<CategoryKind> kind,
      Value<int> sortOrder,
      Value<bool> archived,
    });

final class $$CategoriesTableReferences
    extends BaseReferences<_$LedgerDb, $CategoriesTable, Category> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RecurringsTable, List<Recurring>>
  _recurringsRefsTable(_$LedgerDb db) => MultiTypedResultKey.fromTable(
    db.recurrings,
    aliasName: 'categories__id__recurrings__category_id',
  );

  $$RecurringsTableProcessedTableManager get recurringsRefs {
    final manager = $$RecurringsTableTableManager(
      $_db,
      $_db.recurrings,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_recurringsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TxnsTable, List<Txn>> _txnsRefsTable(
    _$LedgerDb db,
  ) => MultiTypedResultKey.fromTable(
    db.txns,
    aliasName: 'categories__id__txns__category_id',
  );

  $$TxnsTableProcessedTableManager get txnsRefs {
    final manager = $$TxnsTableTableManager(
      $_db,
      $_db.txns,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_txnsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BudgetsTable, List<Budget>> _budgetsRefsTable(
    _$LedgerDb db,
  ) => MultiTypedResultKey.fromTable(
    db.budgets,
    aliasName: 'categories__id__budgets__category_id',
  );

  $$BudgetsTableProcessedTableManager get budgetsRefs {
    final manager = $$BudgetsTableTableManager(
      $_db,
      $_db.budgets,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_budgetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PinnedsTable, List<Pinned>> _pinnedsRefsTable(
    _$LedgerDb db,
  ) => MultiTypedResultKey.fromTable(
    db.pinneds,
    aliasName: 'categories__id__pinneds__category_id',
  );

  $$PinnedsTableProcessedTableManager get pinnedsRefs {
    final manager = $$PinnedsTableTableManager(
      $_db,
      $_db.pinneds,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_pinnedsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$LedgerDb, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<CategoryKind, CategoryKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> recurringsRefs(
    Expression<bool> Function($$RecurringsTableFilterComposer f) f,
  ) {
    final $$RecurringsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recurrings,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringsTableFilterComposer(
            $db: $db,
            $table: $db.recurrings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> txnsRefs(
    Expression<bool> Function($$TxnsTableFilterComposer f) f,
  ) {
    final $$TxnsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.txns,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TxnsTableFilterComposer(
            $db: $db,
            $table: $db.txns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> budgetsRefs(
    Expression<bool> Function($$BudgetsTableFilterComposer f) f,
  ) {
    final $$BudgetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.budgets,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BudgetsTableFilterComposer(
            $db: $db,
            $table: $db.budgets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> pinnedsRefs(
    Expression<bool> Function($$PinnedsTableFilterComposer f) f,
  ) {
    final $$PinnedsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pinneds,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PinnedsTableFilterComposer(
            $db: $db,
            $table: $db.pinneds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$LedgerDb, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$LedgerDb, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumnWithTypeConverter<CategoryKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  Expression<T> recurringsRefs<T extends Object>(
    Expression<T> Function($$RecurringsTableAnnotationComposer a) f,
  ) {
    final $$RecurringsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recurrings,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringsTableAnnotationComposer(
            $db: $db,
            $table: $db.recurrings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> txnsRefs<T extends Object>(
    Expression<T> Function($$TxnsTableAnnotationComposer a) f,
  ) {
    final $$TxnsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.txns,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TxnsTableAnnotationComposer(
            $db: $db,
            $table: $db.txns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> budgetsRefs<T extends Object>(
    Expression<T> Function($$BudgetsTableAnnotationComposer a) f,
  ) {
    final $$BudgetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.budgets,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BudgetsTableAnnotationComposer(
            $db: $db,
            $table: $db.budgets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> pinnedsRefs<T extends Object>(
    Expression<T> Function($$PinnedsTableAnnotationComposer a) f,
  ) {
    final $$PinnedsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pinneds,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PinnedsTableAnnotationComposer(
            $db: $db,
            $table: $db.pinneds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, $$CategoriesTableReferences),
          Category,
          PrefetchHooks Function({
            bool recurringsRefs,
            bool txnsRefs,
            bool budgetsRefs,
            bool pinnedsRefs,
          })
        > {
  $$CategoriesTableTableManager(_$LedgerDb db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<CategoryKind> kind = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                icon: icon,
                kind: kind,
                sortOrder: sortOrder,
                archived: archived,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> icon = const Value.absent(),
                required CategoryKind kind,
                Value<int> sortOrder = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                icon: icon,
                kind: kind,
                sortOrder: sortOrder,
                archived: archived,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                recurringsRefs = false,
                txnsRefs = false,
                budgetsRefs = false,
                pinnedsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (recurringsRefs) db.recurrings,
                    if (txnsRefs) db.txns,
                    if (budgetsRefs) db.budgets,
                    if (pinnedsRefs) db.pinneds,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (recurringsRefs)
                        await $_getPrefetchedData<
                          Category,
                          $CategoriesTable,
                          Recurring
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._recurringsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).recurringsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (txnsRefs)
                        await $_getPrefetchedData<
                          Category,
                          $CategoriesTable,
                          Txn
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._txnsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).txnsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (budgetsRefs)
                        await $_getPrefetchedData<
                          Category,
                          $CategoriesTable,
                          Budget
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._budgetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).budgetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (pinnedsRefs)
                        await $_getPrefetchedData<
                          Category,
                          $CategoriesTable,
                          Pinned
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._pinnedsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).pinnedsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, $$CategoriesTableReferences),
      Category,
      PrefetchHooks Function({
        bool recurringsRefs,
        bool txnsRefs,
        bool budgetsRefs,
        bool pinnedsRefs,
      })
    >;
typedef $$GoalsTableCreateCompanionBuilder =
    GoalsCompanion Function({
      Value<int> id,
      required String name,
      required int targetPaise,
      required GoalKind kind,
      Value<String?> targetDate,
      Value<int?> monthlyPaise,
      Value<bool> archived,
    });
typedef $$GoalsTableUpdateCompanionBuilder =
    GoalsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> targetPaise,
      Value<GoalKind> kind,
      Value<String?> targetDate,
      Value<int?> monthlyPaise,
      Value<bool> archived,
    });

final class $$GoalsTableReferences
    extends BaseReferences<_$LedgerDb, $GoalsTable, Goal> {
  $$GoalsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TxnsTable, List<Txn>> _txnsRefsTable(
    _$LedgerDb db,
  ) => MultiTypedResultKey.fromTable(
    db.txns,
    aliasName: 'goals__id__txns__goal_id',
  );

  $$TxnsTableProcessedTableManager get txnsRefs {
    final manager = $$TxnsTableTableManager(
      $_db,
      $_db.txns,
    ).filter((f) => f.goalId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_txnsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GoalsTableFilterComposer extends Composer<_$LedgerDb, $GoalsTable> {
  $$GoalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetPaise => $composableBuilder(
    column: $table.targetPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<GoalKind, GoalKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get monthlyPaise => $composableBuilder(
    column: $table.monthlyPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> txnsRefs(
    Expression<bool> Function($$TxnsTableFilterComposer f) f,
  ) {
    final $$TxnsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.txns,
      getReferencedColumn: (t) => t.goalId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TxnsTableFilterComposer(
            $db: $db,
            $table: $db.txns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GoalsTableOrderingComposer extends Composer<_$LedgerDb, $GoalsTable> {
  $$GoalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetPaise => $composableBuilder(
    column: $table.targetPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get monthlyPaise => $composableBuilder(
    column: $table.monthlyPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GoalsTableAnnotationComposer extends Composer<_$LedgerDb, $GoalsTable> {
  $$GoalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get targetPaise => $composableBuilder(
    column: $table.targetPaise,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<GoalKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get monthlyPaise => $composableBuilder(
    column: $table.monthlyPaise,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  Expression<T> txnsRefs<T extends Object>(
    Expression<T> Function($$TxnsTableAnnotationComposer a) f,
  ) {
    final $$TxnsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.txns,
      getReferencedColumn: (t) => t.goalId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TxnsTableAnnotationComposer(
            $db: $db,
            $table: $db.txns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GoalsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $GoalsTable,
          Goal,
          $$GoalsTableFilterComposer,
          $$GoalsTableOrderingComposer,
          $$GoalsTableAnnotationComposer,
          $$GoalsTableCreateCompanionBuilder,
          $$GoalsTableUpdateCompanionBuilder,
          (Goal, $$GoalsTableReferences),
          Goal,
          PrefetchHooks Function({bool txnsRefs})
        > {
  $$GoalsTableTableManager(_$LedgerDb db, $GoalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GoalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GoalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GoalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> targetPaise = const Value.absent(),
                Value<GoalKind> kind = const Value.absent(),
                Value<String?> targetDate = const Value.absent(),
                Value<int?> monthlyPaise = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => GoalsCompanion(
                id: id,
                name: name,
                targetPaise: targetPaise,
                kind: kind,
                targetDate: targetDate,
                monthlyPaise: monthlyPaise,
                archived: archived,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int targetPaise,
                required GoalKind kind,
                Value<String?> targetDate = const Value.absent(),
                Value<int?> monthlyPaise = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => GoalsCompanion.insert(
                id: id,
                name: name,
                targetPaise: targetPaise,
                kind: kind,
                targetDate: targetDate,
                monthlyPaise: monthlyPaise,
                archived: archived,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$GoalsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({txnsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (txnsRefs) db.txns],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (txnsRefs)
                    await $_getPrefetchedData<Goal, $GoalsTable, Txn>(
                      currentTable: table,
                      referencedTable: $$GoalsTableReferences._txnsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$GoalsTableReferences(db, table, p0).txnsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.goalId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$GoalsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $GoalsTable,
      Goal,
      $$GoalsTableFilterComposer,
      $$GoalsTableOrderingComposer,
      $$GoalsTableAnnotationComposer,
      $$GoalsTableCreateCompanionBuilder,
      $$GoalsTableUpdateCompanionBuilder,
      (Goal, $$GoalsTableReferences),
      Goal,
      PrefetchHooks Function({bool txnsRefs})
    >;
typedef $$RecurringsTableCreateCompanionBuilder =
    RecurringsCompanion Function({
      Value<int> id,
      required String title,
      required int amountPaise,
      Value<int?> categoryId,
      required int accountId,
      required RecurringKind kind,
      Value<int> everyMonths,
      required int dayOfMonth,
      required String nextDue,
      Value<bool> active,
    });
typedef $$RecurringsTableUpdateCompanionBuilder =
    RecurringsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<int> amountPaise,
      Value<int?> categoryId,
      Value<int> accountId,
      Value<RecurringKind> kind,
      Value<int> everyMonths,
      Value<int> dayOfMonth,
      Value<String> nextDue,
      Value<bool> active,
    });

final class $$RecurringsTableReferences
    extends BaseReferences<_$LedgerDb, $RecurringsTable, Recurring> {
  $$RecurringsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$LedgerDb db) =>
      db.categories.createAlias('recurrings__category_id__categories__id');

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<int>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _accountIdTable(_$LedgerDb db) =>
      db.accounts.createAlias('recurrings__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<int>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TxnsTable, List<Txn>> _txnsRefsTable(
    _$LedgerDb db,
  ) => MultiTypedResultKey.fromTable(
    db.txns,
    aliasName: 'recurrings__id__txns__recurring_id',
  );

  $$TxnsTableProcessedTableManager get txnsRefs {
    final manager = $$TxnsTableTableManager(
      $_db,
      $_db.txns,
    ).filter((f) => f.recurringId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_txnsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RecurringsTableFilterComposer
    extends Composer<_$LedgerDb, $RecurringsTable> {
  $$RecurringsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RecurringKind, RecurringKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get everyMonths => $composableBuilder(
    column: $table.everyMonths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayOfMonth => $composableBuilder(
    column: $table.dayOfMonth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextDue => $composableBuilder(
    column: $table.nextDue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> txnsRefs(
    Expression<bool> Function($$TxnsTableFilterComposer f) f,
  ) {
    final $$TxnsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.txns,
      getReferencedColumn: (t) => t.recurringId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TxnsTableFilterComposer(
            $db: $db,
            $table: $db.txns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecurringsTableOrderingComposer
    extends Composer<_$LedgerDb, $RecurringsTable> {
  $$RecurringsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get everyMonths => $composableBuilder(
    column: $table.everyMonths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayOfMonth => $composableBuilder(
    column: $table.dayOfMonth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextDue => $composableBuilder(
    column: $table.nextDue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecurringsTableAnnotationComposer
    extends Composer<_$LedgerDb, $RecurringsTable> {
  $$RecurringsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<RecurringKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get everyMonths => $composableBuilder(
    column: $table.everyMonths,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dayOfMonth => $composableBuilder(
    column: $table.dayOfMonth,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextDue =>
      $composableBuilder(column: $table.nextDue, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> txnsRefs<T extends Object>(
    Expression<T> Function($$TxnsTableAnnotationComposer a) f,
  ) {
    final $$TxnsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.txns,
      getReferencedColumn: (t) => t.recurringId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TxnsTableAnnotationComposer(
            $db: $db,
            $table: $db.txns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecurringsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $RecurringsTable,
          Recurring,
          $$RecurringsTableFilterComposer,
          $$RecurringsTableOrderingComposer,
          $$RecurringsTableAnnotationComposer,
          $$RecurringsTableCreateCompanionBuilder,
          $$RecurringsTableUpdateCompanionBuilder,
          (Recurring, $$RecurringsTableReferences),
          Recurring,
          PrefetchHooks Function({
            bool categoryId,
            bool accountId,
            bool txnsRefs,
          })
        > {
  $$RecurringsTableTableManager(_$LedgerDb db, $RecurringsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecurringsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecurringsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecurringsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int> accountId = const Value.absent(),
                Value<RecurringKind> kind = const Value.absent(),
                Value<int> everyMonths = const Value.absent(),
                Value<int> dayOfMonth = const Value.absent(),
                Value<String> nextDue = const Value.absent(),
                Value<bool> active = const Value.absent(),
              }) => RecurringsCompanion(
                id: id,
                title: title,
                amountPaise: amountPaise,
                categoryId: categoryId,
                accountId: accountId,
                kind: kind,
                everyMonths: everyMonths,
                dayOfMonth: dayOfMonth,
                nextDue: nextDue,
                active: active,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required int amountPaise,
                Value<int?> categoryId = const Value.absent(),
                required int accountId,
                required RecurringKind kind,
                Value<int> everyMonths = const Value.absent(),
                required int dayOfMonth,
                required String nextDue,
                Value<bool> active = const Value.absent(),
              }) => RecurringsCompanion.insert(
                id: id,
                title: title,
                amountPaise: amountPaise,
                categoryId: categoryId,
                accountId: accountId,
                kind: kind,
                everyMonths: everyMonths,
                dayOfMonth: dayOfMonth,
                nextDue: nextDue,
                active: active,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecurringsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({categoryId = false, accountId = false, txnsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (txnsRefs) db.txns],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable: $$RecurringsTableReferences
                                        ._categoryIdTable(db),
                                    referencedColumn:
                                        $$RecurringsTableReferences
                                            ._categoryIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (accountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.accountId,
                                    referencedTable: $$RecurringsTableReferences
                                        ._accountIdTable(db),
                                    referencedColumn:
                                        $$RecurringsTableReferences
                                            ._accountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (txnsRefs)
                        await $_getPrefetchedData<
                          Recurring,
                          $RecurringsTable,
                          Txn
                        >(
                          currentTable: table,
                          referencedTable: $$RecurringsTableReferences
                              ._txnsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RecurringsTableReferences(
                                db,
                                table,
                                p0,
                              ).txnsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.recurringId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$RecurringsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $RecurringsTable,
      Recurring,
      $$RecurringsTableFilterComposer,
      $$RecurringsTableOrderingComposer,
      $$RecurringsTableAnnotationComposer,
      $$RecurringsTableCreateCompanionBuilder,
      $$RecurringsTableUpdateCompanionBuilder,
      (Recurring, $$RecurringsTableReferences),
      Recurring,
      PrefetchHooks Function({bool categoryId, bool accountId, bool txnsRefs})
    >;
typedef $$TxnsTableCreateCompanionBuilder =
    TxnsCompanion Function({
      Value<int> id,
      required int amountPaise,
      required TxnType type,
      Value<int?> categoryId,
      required int accountId,
      Value<int?> toAccountId,
      required String title,
      Value<String?> note,
      required DateTime at,
      Value<int?> goalId,
      Value<int?> recurringId,
      Value<DateTime> createdAt,
    });
typedef $$TxnsTableUpdateCompanionBuilder =
    TxnsCompanion Function({
      Value<int> id,
      Value<int> amountPaise,
      Value<TxnType> type,
      Value<int?> categoryId,
      Value<int> accountId,
      Value<int?> toAccountId,
      Value<String> title,
      Value<String?> note,
      Value<DateTime> at,
      Value<int?> goalId,
      Value<int?> recurringId,
      Value<DateTime> createdAt,
    });

final class $$TxnsTableReferences
    extends BaseReferences<_$LedgerDb, $TxnsTable, Txn> {
  $$TxnsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$LedgerDb db) =>
      db.categories.createAlias('txns__category_id__categories__id');

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<int>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _accountIdTable(_$LedgerDb db) =>
      db.accounts.createAlias('txns__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<int>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _toAccountIdTable(_$LedgerDb db) =>
      db.accounts.createAlias('txns__to_account_id__accounts__id');

  $$AccountsTableProcessedTableManager? get toAccountId {
    final $_column = $_itemColumn<int>('to_account_id');
    if ($_column == null) return null;
    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_toAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $GoalsTable _goalIdTable(_$LedgerDb db) =>
      db.goals.createAlias('txns__goal_id__goals__id');

  $$GoalsTableProcessedTableManager? get goalId {
    final $_column = $_itemColumn<int>('goal_id');
    if ($_column == null) return null;
    final manager = $$GoalsTableTableManager(
      $_db,
      $_db.goals,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_goalIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $RecurringsTable _recurringIdTable(_$LedgerDb db) =>
      db.recurrings.createAlias('txns__recurring_id__recurrings__id');

  $$RecurringsTableProcessedTableManager? get recurringId {
    final $_column = $_itemColumn<int>('recurring_id');
    if ($_column == null) return null;
    final manager = $$RecurringsTableTableManager(
      $_db,
      $_db.recurrings,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recurringIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TxnsTableFilterComposer extends Composer<_$LedgerDb, $TxnsTable> {
  $$TxnsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TxnType, TxnType, int> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get toAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GoalsTableFilterComposer get goalId {
    final $$GoalsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.goalId,
      referencedTable: $db.goals,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GoalsTableFilterComposer(
            $db: $db,
            $table: $db.goals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecurringsTableFilterComposer get recurringId {
    final $$RecurringsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recurringId,
      referencedTable: $db.recurrings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringsTableFilterComposer(
            $db: $db,
            $table: $db.recurrings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TxnsTableOrderingComposer extends Composer<_$LedgerDb, $TxnsTable> {
  $$TxnsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get toAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GoalsTableOrderingComposer get goalId {
    final $$GoalsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.goalId,
      referencedTable: $db.goals,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GoalsTableOrderingComposer(
            $db: $db,
            $table: $db.goals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecurringsTableOrderingComposer get recurringId {
    final $$RecurringsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recurringId,
      referencedTable: $db.recurrings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringsTableOrderingComposer(
            $db: $db,
            $table: $db.recurrings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TxnsTableAnnotationComposer extends Composer<_$LedgerDb, $TxnsTable> {
  $$TxnsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TxnType, int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get toAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GoalsTableAnnotationComposer get goalId {
    final $$GoalsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.goalId,
      referencedTable: $db.goals,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GoalsTableAnnotationComposer(
            $db: $db,
            $table: $db.goals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecurringsTableAnnotationComposer get recurringId {
    final $$RecurringsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recurringId,
      referencedTable: $db.recurrings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringsTableAnnotationComposer(
            $db: $db,
            $table: $db.recurrings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TxnsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $TxnsTable,
          Txn,
          $$TxnsTableFilterComposer,
          $$TxnsTableOrderingComposer,
          $$TxnsTableAnnotationComposer,
          $$TxnsTableCreateCompanionBuilder,
          $$TxnsTableUpdateCompanionBuilder,
          (Txn, $$TxnsTableReferences),
          Txn,
          PrefetchHooks Function({
            bool categoryId,
            bool accountId,
            bool toAccountId,
            bool goalId,
            bool recurringId,
          })
        > {
  $$TxnsTableTableManager(_$LedgerDb db, $TxnsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TxnsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TxnsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TxnsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<TxnType> type = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int> accountId = const Value.absent(),
                Value<int?> toAccountId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<int?> goalId = const Value.absent(),
                Value<int?> recurringId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TxnsCompanion(
                id: id,
                amountPaise: amountPaise,
                type: type,
                categoryId: categoryId,
                accountId: accountId,
                toAccountId: toAccountId,
                title: title,
                note: note,
                at: at,
                goalId: goalId,
                recurringId: recurringId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int amountPaise,
                required TxnType type,
                Value<int?> categoryId = const Value.absent(),
                required int accountId,
                Value<int?> toAccountId = const Value.absent(),
                required String title,
                Value<String?> note = const Value.absent(),
                required DateTime at,
                Value<int?> goalId = const Value.absent(),
                Value<int?> recurringId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TxnsCompanion.insert(
                id: id,
                amountPaise: amountPaise,
                type: type,
                categoryId: categoryId,
                accountId: accountId,
                toAccountId: toAccountId,
                title: title,
                note: note,
                at: at,
                goalId: goalId,
                recurringId: recurringId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TxnsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                categoryId = false,
                accountId = false,
                toAccountId = false,
                goalId = false,
                recurringId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable: $$TxnsTableReferences
                                        ._categoryIdTable(db),
                                    referencedColumn: $$TxnsTableReferences
                                        ._categoryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (accountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.accountId,
                                    referencedTable: $$TxnsTableReferences
                                        ._accountIdTable(db),
                                    referencedColumn: $$TxnsTableReferences
                                        ._accountIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (toAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.toAccountId,
                                    referencedTable: $$TxnsTableReferences
                                        ._toAccountIdTable(db),
                                    referencedColumn: $$TxnsTableReferences
                                        ._toAccountIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (goalId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.goalId,
                                    referencedTable: $$TxnsTableReferences
                                        ._goalIdTable(db),
                                    referencedColumn: $$TxnsTableReferences
                                        ._goalIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (recurringId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.recurringId,
                                    referencedTable: $$TxnsTableReferences
                                        ._recurringIdTable(db),
                                    referencedColumn: $$TxnsTableReferences
                                        ._recurringIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$TxnsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $TxnsTable,
      Txn,
      $$TxnsTableFilterComposer,
      $$TxnsTableOrderingComposer,
      $$TxnsTableAnnotationComposer,
      $$TxnsTableCreateCompanionBuilder,
      $$TxnsTableUpdateCompanionBuilder,
      (Txn, $$TxnsTableReferences),
      Txn,
      PrefetchHooks Function({
        bool categoryId,
        bool accountId,
        bool toAccountId,
        bool goalId,
        bool recurringId,
      })
    >;
typedef $$BudgetsTableCreateCompanionBuilder =
    BudgetsCompanion Function({
      Value<int> id,
      Value<int?> categoryId,
      required String name,
      required int limitPaise,
      required BudgetPeriod period,
      required BudgetKind kind,
      Value<bool> rollover,
      Value<bool> archived,
    });
typedef $$BudgetsTableUpdateCompanionBuilder =
    BudgetsCompanion Function({
      Value<int> id,
      Value<int?> categoryId,
      Value<String> name,
      Value<int> limitPaise,
      Value<BudgetPeriod> period,
      Value<BudgetKind> kind,
      Value<bool> rollover,
      Value<bool> archived,
    });

final class $$BudgetsTableReferences
    extends BaseReferences<_$LedgerDb, $BudgetsTable, Budget> {
  $$BudgetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$LedgerDb db) =>
      db.categories.createAlias('budgets__category_id__categories__id');

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<int>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BudgetsTableFilterComposer extends Composer<_$LedgerDb, $BudgetsTable> {
  $$BudgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get limitPaise => $composableBuilder(
    column: $table.limitPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BudgetPeriod, BudgetPeriod, int> get period =>
      $composableBuilder(
        column: $table.period,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<BudgetKind, BudgetKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get rollover => $composableBuilder(
    column: $table.rollover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableOrderingComposer
    extends Composer<_$LedgerDb, $BudgetsTable> {
  $$BudgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get limitPaise => $composableBuilder(
    column: $table.limitPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get rollover => $composableBuilder(
    column: $table.rollover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableAnnotationComposer
    extends Composer<_$LedgerDb, $BudgetsTable> {
  $$BudgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get limitPaise => $composableBuilder(
    column: $table.limitPaise,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<BudgetPeriod, int> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BudgetKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get rollover =>
      $composableBuilder(column: $table.rollover, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $BudgetsTable,
          Budget,
          $$BudgetsTableFilterComposer,
          $$BudgetsTableOrderingComposer,
          $$BudgetsTableAnnotationComposer,
          $$BudgetsTableCreateCompanionBuilder,
          $$BudgetsTableUpdateCompanionBuilder,
          (Budget, $$BudgetsTableReferences),
          Budget,
          PrefetchHooks Function({bool categoryId})
        > {
  $$BudgetsTableTableManager(_$LedgerDb db, $BudgetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BudgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BudgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> limitPaise = const Value.absent(),
                Value<BudgetPeriod> period = const Value.absent(),
                Value<BudgetKind> kind = const Value.absent(),
                Value<bool> rollover = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => BudgetsCompanion(
                id: id,
                categoryId: categoryId,
                name: name,
                limitPaise: limitPaise,
                period: period,
                kind: kind,
                rollover: rollover,
                archived: archived,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                required String name,
                required int limitPaise,
                required BudgetPeriod period,
                required BudgetKind kind,
                Value<bool> rollover = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => BudgetsCompanion.insert(
                id: id,
                categoryId: categoryId,
                name: name,
                limitPaise: limitPaise,
                period: period,
                kind: kind,
                rollover: rollover,
                archived: archived,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BudgetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.categoryId,
                                referencedTable: $$BudgetsTableReferences
                                    ._categoryIdTable(db),
                                referencedColumn: $$BudgetsTableReferences
                                    ._categoryIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BudgetsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $BudgetsTable,
      Budget,
      $$BudgetsTableFilterComposer,
      $$BudgetsTableOrderingComposer,
      $$BudgetsTableAnnotationComposer,
      $$BudgetsTableCreateCompanionBuilder,
      $$BudgetsTableUpdateCompanionBuilder,
      (Budget, $$BudgetsTableReferences),
      Budget,
      PrefetchHooks Function({bool categoryId})
    >;
typedef $$PinnedsTableCreateCompanionBuilder =
    PinnedsCompanion Function({
      Value<int> id,
      required String title,
      required int amountPaise,
      required int categoryId,
      required int accountId,
      Value<int> sortOrder,
    });
typedef $$PinnedsTableUpdateCompanionBuilder =
    PinnedsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<int> amountPaise,
      Value<int> categoryId,
      Value<int> accountId,
      Value<int> sortOrder,
    });

final class $$PinnedsTableReferences
    extends BaseReferences<_$LedgerDb, $PinnedsTable, Pinned> {
  $$PinnedsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$LedgerDb db) =>
      db.categories.createAlias('pinneds__category_id__categories__id');

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<int>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _accountIdTable(_$LedgerDb db) =>
      db.accounts.createAlias('pinneds__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<int>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PinnedsTableFilterComposer extends Composer<_$LedgerDb, $PinnedsTable> {
  $$PinnedsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PinnedsTableOrderingComposer
    extends Composer<_$LedgerDb, $PinnedsTable> {
  $$PinnedsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PinnedsTableAnnotationComposer
    extends Composer<_$LedgerDb, $PinnedsTable> {
  $$PinnedsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PinnedsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $PinnedsTable,
          Pinned,
          $$PinnedsTableFilterComposer,
          $$PinnedsTableOrderingComposer,
          $$PinnedsTableAnnotationComposer,
          $$PinnedsTableCreateCompanionBuilder,
          $$PinnedsTableUpdateCompanionBuilder,
          (Pinned, $$PinnedsTableReferences),
          Pinned,
          PrefetchHooks Function({bool categoryId, bool accountId})
        > {
  $$PinnedsTableTableManager(_$LedgerDb db, $PinnedsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PinnedsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PinnedsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PinnedsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<int> categoryId = const Value.absent(),
                Value<int> accountId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => PinnedsCompanion(
                id: id,
                title: title,
                amountPaise: amountPaise,
                categoryId: categoryId,
                accountId: accountId,
                sortOrder: sortOrder,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required int amountPaise,
                required int categoryId,
                required int accountId,
                Value<int> sortOrder = const Value.absent(),
              }) => PinnedsCompanion.insert(
                id: id,
                title: title,
                amountPaise: amountPaise,
                categoryId: categoryId,
                accountId: accountId,
                sortOrder: sortOrder,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PinnedsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false, accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.categoryId,
                                referencedTable: $$PinnedsTableReferences
                                    ._categoryIdTable(db),
                                referencedColumn: $$PinnedsTableReferences
                                    ._categoryIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable: $$PinnedsTableReferences
                                    ._accountIdTable(db),
                                referencedColumn: $$PinnedsTableReferences
                                    ._accountIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PinnedsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $PinnedsTable,
      Pinned,
      $$PinnedsTableFilterComposer,
      $$PinnedsTableOrderingComposer,
      $$PinnedsTableAnnotationComposer,
      $$PinnedsTableCreateCompanionBuilder,
      $$PinnedsTableUpdateCompanionBuilder,
      (Pinned, $$PinnedsTableReferences),
      Pinned,
      PrefetchHooks Function({bool categoryId, bool accountId})
    >;
typedef $$DaySealsTableCreateCompanionBuilder =
    DaySealsCompanion Function({
      required String date,
      Value<DateTime> sealedAt,
      Value<int> rowid,
    });
typedef $$DaySealsTableUpdateCompanionBuilder =
    DaySealsCompanion Function({
      Value<String> date,
      Value<DateTime> sealedAt,
      Value<int> rowid,
    });

class $$DaySealsTableFilterComposer
    extends Composer<_$LedgerDb, $DaySealsTable> {
  $$DaySealsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sealedAt => $composableBuilder(
    column: $table.sealedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DaySealsTableOrderingComposer
    extends Composer<_$LedgerDb, $DaySealsTable> {
  $$DaySealsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sealedAt => $composableBuilder(
    column: $table.sealedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DaySealsTableAnnotationComposer
    extends Composer<_$LedgerDb, $DaySealsTable> {
  $$DaySealsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<DateTime> get sealedAt =>
      $composableBuilder(column: $table.sealedAt, builder: (column) => column);
}

class $$DaySealsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $DaySealsTable,
          DaySeal,
          $$DaySealsTableFilterComposer,
          $$DaySealsTableOrderingComposer,
          $$DaySealsTableAnnotationComposer,
          $$DaySealsTableCreateCompanionBuilder,
          $$DaySealsTableUpdateCompanionBuilder,
          (DaySeal, BaseReferences<_$LedgerDb, $DaySealsTable, DaySeal>),
          DaySeal,
          PrefetchHooks Function()
        > {
  $$DaySealsTableTableManager(_$LedgerDb db, $DaySealsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DaySealsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DaySealsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DaySealsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<DateTime> sealedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DaySealsCompanion(
                date: date,
                sealedAt: sealedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                Value<DateTime> sealedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DaySealsCompanion.insert(
                date: date,
                sealedAt: sealedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DaySealsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $DaySealsTable,
      DaySeal,
      $$DaySealsTableFilterComposer,
      $$DaySealsTableOrderingComposer,
      $$DaySealsTableAnnotationComposer,
      $$DaySealsTableCreateCompanionBuilder,
      $$DaySealsTableUpdateCompanionBuilder,
      (DaySeal, BaseReferences<_$LedgerDb, $DaySealsTable, DaySeal>),
      DaySeal,
      PrefetchHooks Function()
    >;
typedef $$ActivitiesTableCreateCompanionBuilder =
    ActivitiesCompanion Function({
      Value<int> id,
      required int txnId,
      required ActivityAction action,
      required String snapshot,
      Value<DateTime> at,
    });
typedef $$ActivitiesTableUpdateCompanionBuilder =
    ActivitiesCompanion Function({
      Value<int> id,
      Value<int> txnId,
      Value<ActivityAction> action,
      Value<String> snapshot,
      Value<DateTime> at,
    });

class $$ActivitiesTableFilterComposer
    extends Composer<_$LedgerDb, $ActivitiesTable> {
  $$ActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get txnId => $composableBuilder(
    column: $table.txnId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ActivityAction, ActivityAction, int>
  get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ActivitiesTableOrderingComposer
    extends Composer<_$LedgerDb, $ActivitiesTable> {
  $$ActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get txnId => $composableBuilder(
    column: $table.txnId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivitiesTableAnnotationComposer
    extends Composer<_$LedgerDb, $ActivitiesTable> {
  $$ActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get txnId =>
      $composableBuilder(column: $table.txnId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ActivityAction, int> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);
}

class $$ActivitiesTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $ActivitiesTable,
          Activity,
          $$ActivitiesTableFilterComposer,
          $$ActivitiesTableOrderingComposer,
          $$ActivitiesTableAnnotationComposer,
          $$ActivitiesTableCreateCompanionBuilder,
          $$ActivitiesTableUpdateCompanionBuilder,
          (Activity, BaseReferences<_$LedgerDb, $ActivitiesTable, Activity>),
          Activity,
          PrefetchHooks Function()
        > {
  $$ActivitiesTableTableManager(_$LedgerDb db, $ActivitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> txnId = const Value.absent(),
                Value<ActivityAction> action = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
              }) => ActivitiesCompanion(
                id: id,
                txnId: txnId,
                action: action,
                snapshot: snapshot,
                at: at,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int txnId,
                required ActivityAction action,
                required String snapshot,
                Value<DateTime> at = const Value.absent(),
              }) => ActivitiesCompanion.insert(
                id: id,
                txnId: txnId,
                action: action,
                snapshot: snapshot,
                at: at,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $ActivitiesTable,
      Activity,
      $$ActivitiesTableFilterComposer,
      $$ActivitiesTableOrderingComposer,
      $$ActivitiesTableAnnotationComposer,
      $$ActivitiesTableCreateCompanionBuilder,
      $$ActivitiesTableUpdateCompanionBuilder,
      (Activity, BaseReferences<_$LedgerDb, $ActivitiesTable, Activity>),
      Activity,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$LedgerDb, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$LedgerDb, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$LedgerDb, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$LedgerDb, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$LedgerDb db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$LedgerDb, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> body,
      Value<bool> pinned,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> archived,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> body,
      Value<bool> pinned,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> archived,
    });

class $$NotesTableFilterComposer extends Composer<_$LedgerDb, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer extends Composer<_$LedgerDb, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer extends Composer<_$LedgerDb, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $NotesTable,
          Note,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (Note, BaseReferences<_$LedgerDb, $NotesTable, Note>),
          Note,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$LedgerDb db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                title: title,
                body: body,
                pinned: pinned,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archived: archived,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                title: title,
                body: body,
                pinned: pinned,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archived: archived,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $NotesTable,
      Note,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (Note, BaseReferences<_$LedgerDb, $NotesTable, Note>),
      Note,
      PrefetchHooks Function()
    >;
typedef $$FocusSessionsTableCreateCompanionBuilder =
    FocusSessionsCompanion Function({
      Value<int> id,
      required DateTime startedAt,
      required int minutes,
      required FocusKind kind,
      Value<bool> completed,
      Value<String?> label,
    });
typedef $$FocusSessionsTableUpdateCompanionBuilder =
    FocusSessionsCompanion Function({
      Value<int> id,
      Value<DateTime> startedAt,
      Value<int> minutes,
      Value<FocusKind> kind,
      Value<bool> completed,
      Value<String?> label,
    });

class $$FocusSessionsTableFilterComposer
    extends Composer<_$LedgerDb, $FocusSessionsTable> {
  $$FocusSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minutes => $composableBuilder(
    column: $table.minutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<FocusKind, FocusKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusSessionsTableOrderingComposer
    extends Composer<_$LedgerDb, $FocusSessionsTable> {
  $$FocusSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minutes => $composableBuilder(
    column: $table.minutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusSessionsTableAnnotationComposer
    extends Composer<_$LedgerDb, $FocusSessionsTable> {
  $$FocusSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get minutes =>
      $composableBuilder(column: $table.minutes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FocusKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);
}

class $$FocusSessionsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $FocusSessionsTable,
          FocusSession,
          $$FocusSessionsTableFilterComposer,
          $$FocusSessionsTableOrderingComposer,
          $$FocusSessionsTableAnnotationComposer,
          $$FocusSessionsTableCreateCompanionBuilder,
          $$FocusSessionsTableUpdateCompanionBuilder,
          (
            FocusSession,
            BaseReferences<_$LedgerDb, $FocusSessionsTable, FocusSession>,
          ),
          FocusSession,
          PrefetchHooks Function()
        > {
  $$FocusSessionsTableTableManager(_$LedgerDb db, $FocusSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<int> minutes = const Value.absent(),
                Value<FocusKind> kind = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<String?> label = const Value.absent(),
              }) => FocusSessionsCompanion(
                id: id,
                startedAt: startedAt,
                minutes: minutes,
                kind: kind,
                completed: completed,
                label: label,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime startedAt,
                required int minutes,
                required FocusKind kind,
                Value<bool> completed = const Value.absent(),
                Value<String?> label = const Value.absent(),
              }) => FocusSessionsCompanion.insert(
                id: id,
                startedAt: startedAt,
                minutes: minutes,
                kind: kind,
                completed: completed,
                label: label,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FocusSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $FocusSessionsTable,
      FocusSession,
      $$FocusSessionsTableFilterComposer,
      $$FocusSessionsTableOrderingComposer,
      $$FocusSessionsTableAnnotationComposer,
      $$FocusSessionsTableCreateCompanionBuilder,
      $$FocusSessionsTableUpdateCompanionBuilder,
      (
        FocusSession,
        BaseReferences<_$LedgerDb, $FocusSessionsTable, FocusSession>,
      ),
      FocusSession,
      PrefetchHooks Function()
    >;
typedef $$JournalEntriesTableCreateCompanionBuilder =
    JournalEntriesCompanion Function({
      required String date,
      Value<String> body,
      Value<int?> mood,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$JournalEntriesTableUpdateCompanionBuilder =
    JournalEntriesCompanion Function({
      Value<String> date,
      Value<String> body,
      Value<int?> mood,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$JournalEntriesTableFilterComposer
    extends Composer<_$LedgerDb, $JournalEntriesTable> {
  $$JournalEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$JournalEntriesTableOrderingComposer
    extends Composer<_$LedgerDb, $JournalEntriesTable> {
  $$JournalEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JournalEntriesTableAnnotationComposer
    extends Composer<_$LedgerDb, $JournalEntriesTable> {
  $$JournalEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$JournalEntriesTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $JournalEntriesTable,
          JournalEntry,
          $$JournalEntriesTableFilterComposer,
          $$JournalEntriesTableOrderingComposer,
          $$JournalEntriesTableAnnotationComposer,
          $$JournalEntriesTableCreateCompanionBuilder,
          $$JournalEntriesTableUpdateCompanionBuilder,
          (
            JournalEntry,
            BaseReferences<_$LedgerDb, $JournalEntriesTable, JournalEntry>,
          ),
          JournalEntry,
          PrefetchHooks Function()
        > {
  $$JournalEntriesTableTableManager(_$LedgerDb db, $JournalEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int?> mood = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesCompanion(
                date: date,
                body: body,
                mood: mood,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                Value<String> body = const Value.absent(),
                Value<int?> mood = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesCompanion.insert(
                date: date,
                body: body,
                mood: mood,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$JournalEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $JournalEntriesTable,
      JournalEntry,
      $$JournalEntriesTableFilterComposer,
      $$JournalEntriesTableOrderingComposer,
      $$JournalEntriesTableAnnotationComposer,
      $$JournalEntriesTableCreateCompanionBuilder,
      $$JournalEntriesTableUpdateCompanionBuilder,
      (
        JournalEntry,
        BaseReferences<_$LedgerDb, $JournalEntriesTable, JournalEntry>,
      ),
      JournalEntry,
      PrefetchHooks Function()
    >;
typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      required String title,
      Value<String?> note,
      required String date,
      Value<int?> timeMinutes,
      Value<EventRepeat> repeat,
      Value<DateTime> createdAt,
      Value<bool> archived,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String?> note,
      Value<String> date,
      Value<int?> timeMinutes,
      Value<EventRepeat> repeat,
      Value<DateTime> createdAt,
      Value<bool> archived,
    });

class $$EventsTableFilterComposer extends Composer<_$LedgerDb, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeMinutes => $composableBuilder(
    column: $table.timeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EventRepeat, EventRepeat, int> get repeat =>
      $composableBuilder(
        column: $table.repeat,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer extends Composer<_$LedgerDb, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeMinutes => $composableBuilder(
    column: $table.timeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeat => $composableBuilder(
    column: $table.repeat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$LedgerDb, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get timeMinutes => $composableBuilder(
    column: $table.timeMinutes,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<EventRepeat, int> get repeat =>
      $composableBuilder(column: $table.repeat, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, BaseReferences<_$LedgerDb, $EventsTable, Event>),
          Event,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$LedgerDb db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int?> timeMinutes = const Value.absent(),
                Value<EventRepeat> repeat = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                title: title,
                note: note,
                date: date,
                timeMinutes: timeMinutes,
                repeat: repeat,
                createdAt: createdAt,
                archived: archived,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String?> note = const Value.absent(),
                required String date,
                Value<int?> timeMinutes = const Value.absent(),
                Value<EventRepeat> repeat = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> archived = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                title: title,
                note: note,
                date: date,
                timeMinutes: timeMinutes,
                repeat: repeat,
                createdAt: createdAt,
                archived: archived,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, BaseReferences<_$LedgerDb, $EventsTable, Event>),
      Event,
      PrefetchHooks Function()
    >;
typedef $$VaultItemsTableCreateCompanionBuilder =
    VaultItemsCompanion Function({
      Value<int> id,
      required String nonce,
      required String cipher,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$VaultItemsTableUpdateCompanionBuilder =
    VaultItemsCompanion Function({
      Value<int> id,
      Value<String> nonce,
      Value<String> cipher,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$VaultItemsTableFilterComposer
    extends Composer<_$LedgerDb, $VaultItemsTable> {
  $$VaultItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cipher => $composableBuilder(
    column: $table.cipher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VaultItemsTableOrderingComposer
    extends Composer<_$LedgerDb, $VaultItemsTable> {
  $$VaultItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cipher => $composableBuilder(
    column: $table.cipher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VaultItemsTableAnnotationComposer
    extends Composer<_$LedgerDb, $VaultItemsTable> {
  $$VaultItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<String> get cipher =>
      $composableBuilder(column: $table.cipher, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VaultItemsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $VaultItemsTable,
          VaultItem,
          $$VaultItemsTableFilterComposer,
          $$VaultItemsTableOrderingComposer,
          $$VaultItemsTableAnnotationComposer,
          $$VaultItemsTableCreateCompanionBuilder,
          $$VaultItemsTableUpdateCompanionBuilder,
          (VaultItem, BaseReferences<_$LedgerDb, $VaultItemsTable, VaultItem>),
          VaultItem,
          PrefetchHooks Function()
        > {
  $$VaultItemsTableTableManager(_$LedgerDb db, $VaultItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VaultItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VaultItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VaultItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> nonce = const Value.absent(),
                Value<String> cipher = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => VaultItemsCompanion(
                id: id,
                nonce: nonce,
                cipher: cipher,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String nonce,
                required String cipher,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => VaultItemsCompanion.insert(
                id: id,
                nonce: nonce,
                cipher: cipher,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VaultItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $VaultItemsTable,
      VaultItem,
      $$VaultItemsTableFilterComposer,
      $$VaultItemsTableOrderingComposer,
      $$VaultItemsTableAnnotationComposer,
      $$VaultItemsTableCreateCompanionBuilder,
      $$VaultItemsTableUpdateCompanionBuilder,
      (VaultItem, BaseReferences<_$LedgerDb, $VaultItemsTable, VaultItem>),
      VaultItem,
      PrefetchHooks Function()
    >;
typedef $$BalanceSnapshotsTableCreateCompanionBuilder =
    BalanceSnapshotsCompanion Function({
      required int accountId,
      required String date,
      required int balancePaise,
      Value<int> rowid,
    });
typedef $$BalanceSnapshotsTableUpdateCompanionBuilder =
    BalanceSnapshotsCompanion Function({
      Value<int> accountId,
      Value<String> date,
      Value<int> balancePaise,
      Value<int> rowid,
    });

final class $$BalanceSnapshotsTableReferences
    extends
        BaseReferences<_$LedgerDb, $BalanceSnapshotsTable, BalanceSnapshot> {
  $$BalanceSnapshotsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AccountsTable _accountIdTable(_$LedgerDb db) =>
      db.accounts.createAlias('balance_snapshots__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<int>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BalanceSnapshotsTableFilterComposer
    extends Composer<_$LedgerDb, $BalanceSnapshotsTable> {
  $$BalanceSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BalanceSnapshotsTableOrderingComposer
    extends Composer<_$LedgerDb, $BalanceSnapshotsTable> {
  $$BalanceSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BalanceSnapshotsTableAnnotationComposer
    extends Composer<_$LedgerDb, $BalanceSnapshotsTable> {
  $$BalanceSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => column,
  );

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BalanceSnapshotsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $BalanceSnapshotsTable,
          BalanceSnapshot,
          $$BalanceSnapshotsTableFilterComposer,
          $$BalanceSnapshotsTableOrderingComposer,
          $$BalanceSnapshotsTableAnnotationComposer,
          $$BalanceSnapshotsTableCreateCompanionBuilder,
          $$BalanceSnapshotsTableUpdateCompanionBuilder,
          (BalanceSnapshot, $$BalanceSnapshotsTableReferences),
          BalanceSnapshot,
          PrefetchHooks Function({bool accountId})
        > {
  $$BalanceSnapshotsTableTableManager(
    _$LedgerDb db,
    $BalanceSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BalanceSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BalanceSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BalanceSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> accountId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> balancePaise = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BalanceSnapshotsCompanion(
                accountId: accountId,
                date: date,
                balancePaise: balancePaise,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int accountId,
                required String date,
                required int balancePaise,
                Value<int> rowid = const Value.absent(),
              }) => BalanceSnapshotsCompanion.insert(
                accountId: accountId,
                date: date,
                balancePaise: balancePaise,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BalanceSnapshotsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable:
                                    $$BalanceSnapshotsTableReferences
                                        ._accountIdTable(db),
                                referencedColumn:
                                    $$BalanceSnapshotsTableReferences
                                        ._accountIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BalanceSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $BalanceSnapshotsTable,
      BalanceSnapshot,
      $$BalanceSnapshotsTableFilterComposer,
      $$BalanceSnapshotsTableOrderingComposer,
      $$BalanceSnapshotsTableAnnotationComposer,
      $$BalanceSnapshotsTableCreateCompanionBuilder,
      $$BalanceSnapshotsTableUpdateCompanionBuilder,
      (BalanceSnapshot, $$BalanceSnapshotsTableReferences),
      BalanceSnapshot,
      PrefetchHooks Function({bool accountId})
    >;
typedef $$RemoteIdsTableCreateCompanionBuilder =
    RemoteIdsCompanion Function({
      required String kind,
      required int localId,
      required String remoteId,
      Value<DateTime?> syncedAt,
      Value<int> rowid,
    });
typedef $$RemoteIdsTableUpdateCompanionBuilder =
    RemoteIdsCompanion Function({
      Value<String> kind,
      Value<int> localId,
      Value<String> remoteId,
      Value<DateTime?> syncedAt,
      Value<int> rowid,
    });

class $$RemoteIdsTableFilterComposer
    extends Composer<_$LedgerDb, $RemoteIdsTable> {
  $$RemoteIdsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteIdsTableOrderingComposer
    extends Composer<_$LedgerDb, $RemoteIdsTable> {
  $$RemoteIdsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteIdsTableAnnotationComposer
    extends Composer<_$LedgerDb, $RemoteIdsTable> {
  $$RemoteIdsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$RemoteIdsTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $RemoteIdsTable,
          RemoteId,
          $$RemoteIdsTableFilterComposer,
          $$RemoteIdsTableOrderingComposer,
          $$RemoteIdsTableAnnotationComposer,
          $$RemoteIdsTableCreateCompanionBuilder,
          $$RemoteIdsTableUpdateCompanionBuilder,
          (RemoteId, BaseReferences<_$LedgerDb, $RemoteIdsTable, RemoteId>),
          RemoteId,
          PrefetchHooks Function()
        > {
  $$RemoteIdsTableTableManager(_$LedgerDb db, $RemoteIdsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteIdsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteIdsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteIdsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<int> localId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteIdsCompanion(
                kind: kind,
                localId: localId,
                remoteId: remoteId,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required int localId,
                required String remoteId,
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteIdsCompanion.insert(
                kind: kind,
                localId: localId,
                remoteId: remoteId,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteIdsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $RemoteIdsTable,
      RemoteId,
      $$RemoteIdsTableFilterComposer,
      $$RemoteIdsTableOrderingComposer,
      $$RemoteIdsTableAnnotationComposer,
      $$RemoteIdsTableCreateCompanionBuilder,
      $$RemoteIdsTableUpdateCompanionBuilder,
      (RemoteId, BaseReferences<_$LedgerDb, $RemoteIdsTable, RemoteId>),
      RemoteId,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> id,
      required String kind,
      required int localId,
      required String remoteId,
      required OutboxOp op,
      Value<String?> payload,
      Value<DateTime> queuedAt,
      Value<int> attempts,
      Value<String?> lastError,
    });
typedef $$OutboxTableUpdateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<int> localId,
      Value<String> remoteId,
      Value<OutboxOp> op,
      Value<String?> payload,
      Value<DateTime> queuedAt,
      Value<int> attempts,
      Value<String?> lastError,
    });

class $$OutboxTableFilterComposer extends Composer<_$LedgerDb, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<OutboxOp, OutboxOp, int> get op =>
      $composableBuilder(
        column: $table.op,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get queuedAt => $composableBuilder(
    column: $table.queuedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer extends Composer<_$LedgerDb, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get queuedAt => $composableBuilder(
    column: $table.queuedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$LedgerDb, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<OutboxOp, int> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get queuedAt =>
      $composableBuilder(column: $table.queuedAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $OutboxTable,
          OutboxData,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (OutboxData, BaseReferences<_$LedgerDb, $OutboxTable, OutboxData>),
          OutboxData,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$LedgerDb db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> localId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<OutboxOp> op = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<DateTime> queuedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion(
                id: id,
                kind: kind,
                localId: localId,
                remoteId: remoteId,
                op: op,
                payload: payload,
                queuedAt: queuedAt,
                attempts: attempts,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required int localId,
                required String remoteId,
                required OutboxOp op,
                Value<String?> payload = const Value.absent(),
                Value<DateTime> queuedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion.insert(
                id: id,
                kind: kind,
                localId: localId,
                remoteId: remoteId,
                op: op,
                payload: payload,
                queuedAt: queuedAt,
                attempts: attempts,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $OutboxTable,
      OutboxData,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxData, BaseReferences<_$LedgerDb, $OutboxTable, OutboxData>),
      OutboxData,
      PrefetchHooks Function()
    >;
typedef $$DayMarksTableCreateCompanionBuilder =
    DayMarksCompanion Function({
      Value<int> id,
      required String date,
      required String kind,
      Value<String?> note,
      Value<DateTime> at,
    });
typedef $$DayMarksTableUpdateCompanionBuilder =
    DayMarksCompanion Function({
      Value<int> id,
      Value<String> date,
      Value<String> kind,
      Value<String?> note,
      Value<DateTime> at,
    });

class $$DayMarksTableFilterComposer
    extends Composer<_$LedgerDb, $DayMarksTable> {
  $$DayMarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DayMarksTableOrderingComposer
    extends Composer<_$LedgerDb, $DayMarksTable> {
  $$DayMarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DayMarksTableAnnotationComposer
    extends Composer<_$LedgerDb, $DayMarksTable> {
  $$DayMarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);
}

class $$DayMarksTableTableManager
    extends
        RootTableManager<
          _$LedgerDb,
          $DayMarksTable,
          DayMark,
          $$DayMarksTableFilterComposer,
          $$DayMarksTableOrderingComposer,
          $$DayMarksTableAnnotationComposer,
          $$DayMarksTableCreateCompanionBuilder,
          $$DayMarksTableUpdateCompanionBuilder,
          (DayMark, BaseReferences<_$LedgerDb, $DayMarksTable, DayMark>),
          DayMark,
          PrefetchHooks Function()
        > {
  $$DayMarksTableTableManager(_$LedgerDb db, $DayMarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DayMarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DayMarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DayMarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
              }) => DayMarksCompanion(
                id: id,
                date: date,
                kind: kind,
                note: note,
                at: at,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String date,
                required String kind,
                Value<String?> note = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
              }) => DayMarksCompanion.insert(
                id: id,
                date: date,
                kind: kind,
                note: note,
                at: at,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DayMarksTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDb,
      $DayMarksTable,
      DayMark,
      $$DayMarksTableFilterComposer,
      $$DayMarksTableOrderingComposer,
      $$DayMarksTableAnnotationComposer,
      $$DayMarksTableCreateCompanionBuilder,
      $$DayMarksTableUpdateCompanionBuilder,
      (DayMark, BaseReferences<_$LedgerDb, $DayMarksTable, DayMark>),
      DayMark,
      PrefetchHooks Function()
    >;

class $LedgerDbManager {
  final _$LedgerDb _db;
  $LedgerDbManager(this._db);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$GoalsTableTableManager get goals =>
      $$GoalsTableTableManager(_db, _db.goals);
  $$RecurringsTableTableManager get recurrings =>
      $$RecurringsTableTableManager(_db, _db.recurrings);
  $$TxnsTableTableManager get txns => $$TxnsTableTableManager(_db, _db.txns);
  $$BudgetsTableTableManager get budgets =>
      $$BudgetsTableTableManager(_db, _db.budgets);
  $$PinnedsTableTableManager get pinneds =>
      $$PinnedsTableTableManager(_db, _db.pinneds);
  $$DaySealsTableTableManager get daySeals =>
      $$DaySealsTableTableManager(_db, _db.daySeals);
  $$ActivitiesTableTableManager get activities =>
      $$ActivitiesTableTableManager(_db, _db.activities);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$FocusSessionsTableTableManager get focusSessions =>
      $$FocusSessionsTableTableManager(_db, _db.focusSessions);
  $$JournalEntriesTableTableManager get journalEntries =>
      $$JournalEntriesTableTableManager(_db, _db.journalEntries);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$VaultItemsTableTableManager get vaultItems =>
      $$VaultItemsTableTableManager(_db, _db.vaultItems);
  $$BalanceSnapshotsTableTableManager get balanceSnapshots =>
      $$BalanceSnapshotsTableTableManager(_db, _db.balanceSnapshots);
  $$RemoteIdsTableTableManager get remoteIds =>
      $$RemoteIdsTableTableManager(_db, _db.remoteIds);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$DayMarksTableTableManager get dayMarks =>
      $$DayMarksTableTableManager(_db, _db.dayMarks);
}
