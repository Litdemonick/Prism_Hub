// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prismhub_detail.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPrismHubDetailCollection on Isar {
  IsarCollection<PrismHubDetail> get PrismHubDetails => this.collection();
}

const PrismHubDetailSchema = CollectionSchema(
  name: r'PrismHubDetail',
  id: 1216732533843362544,
  properties: {
    r'aniListID': PropertySchema(
      id: 0,
      name: r'aniListID',
      type: IsarType.string,
    ),
    r'data': PropertySchema(
      id: 1,
      name: r'data',
      type: IsarType.string,
    ),
    r'package': PropertySchema(
      id: 2,
      name: r'package',
      type: IsarType.string,
    ),
    r'tmdbID': PropertySchema(
      id: 3,
      name: r'tmdbID',
      type: IsarType.long,
    ),
    r'updateTime': PropertySchema(
      id: 4,
      name: r'updateTime',
      type: IsarType.dateTime,
    ),
    r'url': PropertySchema(
      id: 5,
      name: r'url',
      type: IsarType.string,
    )
  },
  estimateSize: _PrismHubDetailEstimateSize,
  serialize: _PrismHubDetailSerialize,
  deserialize: _PrismHubDetailDeserialize,
  deserializeProp: _PrismHubDetailDeserializeProp,
  idName: r'id',
  indexes: {
    r'package&url': IndexSchema(
      id: 1543775085104464922,
      name: r'package&url',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'package',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'url',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _PrismHubDetailGetId,
  getLinks: _PrismHubDetailGetLinks,
  attach: _PrismHubDetailAttach,
  version: '3.1.0+1',
);

int _PrismHubDetailEstimateSize(
  PrismHubDetail object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.aniListID;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.data.length * 3;
  bytesCount += 3 + object.package.length * 3;
  bytesCount += 3 + object.url.length * 3;
  return bytesCount;
}

void _PrismHubDetailSerialize(
  PrismHubDetail object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.aniListID);
  writer.writeString(offsets[1], object.data);
  writer.writeString(offsets[2], object.package);
  writer.writeLong(offsets[3], object.tmdbID);
  writer.writeDateTime(offsets[4], object.updateTime);
  writer.writeString(offsets[5], object.url);
}

PrismHubDetail _PrismHubDetailDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PrismHubDetail();
  object.aniListID = reader.readStringOrNull(offsets[0]);
  object.data = reader.readString(offsets[1]);
  object.id = id;
  object.package = reader.readString(offsets[2]);
  object.tmdbID = reader.readLongOrNull(offsets[3]);
  object.updateTime = reader.readDateTime(offsets[4]);
  object.url = reader.readString(offsets[5]);
  return object;
}

P _PrismHubDetailDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLongOrNull(offset)) as P;
    case 4:
      return (reader.readDateTime(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _PrismHubDetailGetId(PrismHubDetail object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _PrismHubDetailGetLinks(PrismHubDetail object) {
  return [];
}

void _PrismHubDetailAttach(
    IsarCollection<dynamic> col, Id id, PrismHubDetail object) {
  object.id = id;
}

extension PrismHubDetailQueryWhereSort
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QWhere> {
  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension PrismHubDetailQueryWhere
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QWhereClause> {
  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause>
      packageEqualToAnyUrl(String package) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'package&url',
        value: [package],
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause>
      packageNotEqualToAnyUrl(String package) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'package&url',
              lower: [],
              upper: [package],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'package&url',
              lower: [package],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'package&url',
              lower: [package],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'package&url',
              lower: [],
              upper: [package],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause>
      packageUrlEqualTo(String package, String url) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'package&url',
        value: [package, url],
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterWhereClause>
      packageEqualToUrlNotEqualTo(String package, String url) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'package&url',
              lower: [package],
              upper: [package, url],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'package&url',
              lower: [package, url],
              includeLower: false,
              upper: [package],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'package&url',
              lower: [package, url],
              includeLower: false,
              upper: [package],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'package&url',
              lower: [package],
              upper: [package, url],
              includeUpper: false,
            ));
      }
    });
  }
}

extension PrismHubDetailQueryFilter
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QFilterCondition> {
  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'aniListID',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'aniListID',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aniListID',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'aniListID',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'aniListID',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'aniListID',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'aniListID',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'aniListID',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'aniListID',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'aniListID',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aniListID',
        value: '',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      aniListIDIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'aniListID',
        value: '',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> dataEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      dataGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      dataLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> dataBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'data',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      dataStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      dataEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      dataContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> dataMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'data',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      dataIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'data',
        value: '',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      dataIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'data',
        value: '',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'package',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'package',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'package',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'package',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'package',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'package',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'package',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'package',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'package',
        value: '',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      packageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'package',
        value: '',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      tmdbIDIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'tmdbID',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      tmdbIDIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'tmdbID',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      tmdbIDEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tmdbID',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      tmdbIDGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tmdbID',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      tmdbIDLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tmdbID',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      tmdbIDBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tmdbID',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      updateTimeEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updateTime',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      updateTimeGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updateTime',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      updateTimeLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updateTime',
        value: value,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      updateTimeBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updateTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> urlEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'url',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      urlGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'url',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> urlLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'url',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> urlBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'url',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      urlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'url',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> urlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'url',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> urlContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'url',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition> urlMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'url',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      urlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'url',
        value: '',
      ));
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterFilterCondition>
      urlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'url',
        value: '',
      ));
    });
  }
}

extension PrismHubDetailQueryObject
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QFilterCondition> {}

extension PrismHubDetailQueryLinks
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QFilterCondition> {}

extension PrismHubDetailQuerySortBy
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QSortBy> {
  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByAniListID() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aniListID', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy>
      sortByAniListIDDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aniListID', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByData() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByDataDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByPackage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'package', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByPackageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'package', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByTmdbID() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tmdbID', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByTmdbIDDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tmdbID', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByUpdateTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updateTime', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy>
      sortByUpdateTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updateTime', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'url', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> sortByUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'url', Sort.desc);
    });
  }
}

extension PrismHubDetailQuerySortThenBy
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QSortThenBy> {
  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByAniListID() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aniListID', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy>
      thenByAniListIDDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aniListID', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByData() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByDataDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByPackage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'package', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByPackageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'package', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByTmdbID() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tmdbID', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByTmdbIDDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tmdbID', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByUpdateTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updateTime', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy>
      thenByUpdateTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updateTime', Sort.desc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'url', Sort.asc);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QAfterSortBy> thenByUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'url', Sort.desc);
    });
  }
}

extension PrismHubDetailQueryWhereDistinct
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QDistinct> {
  QueryBuilder<PrismHubDetail, PrismHubDetail, QDistinct> distinctByAniListID(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'aniListID', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QDistinct> distinctByData(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'data', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QDistinct> distinctByPackage(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'package', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QDistinct> distinctByTmdbID() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tmdbID');
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QDistinct> distinctByUpdateTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updateTime');
    });
  }

  QueryBuilder<PrismHubDetail, PrismHubDetail, QDistinct> distinctByUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'url', caseSensitive: caseSensitive);
    });
  }
}

extension PrismHubDetailQueryProperty
    on QueryBuilder<PrismHubDetail, PrismHubDetail, QQueryProperty> {
  QueryBuilder<PrismHubDetail, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<PrismHubDetail, String?, QQueryOperations> aniListIDProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'aniListID');
    });
  }

  QueryBuilder<PrismHubDetail, String, QQueryOperations> dataProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'data');
    });
  }

  QueryBuilder<PrismHubDetail, String, QQueryOperations> packageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'package');
    });
  }

  QueryBuilder<PrismHubDetail, int?, QQueryOperations> tmdbIDProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tmdbID');
    });
  }

  QueryBuilder<PrismHubDetail, DateTime, QQueryOperations> updateTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updateTime');
    });
  }

  QueryBuilder<PrismHubDetail, String, QQueryOperations> urlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'url');
    });
  }
}
