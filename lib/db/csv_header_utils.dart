/// Utilities for normalizing CSV headers and checking presence with synonyms.
String normalizeHeader(String h) {
  return h.trim().toLowerCase().replaceAll('_', '').replaceAll(' ', '');
}

/// Map of canonical field -> list of accepted synonyms (normalized).
final Map<String, List<String>> headerSynonyms = {
  'id': ['id', 'identifier'],
  'name': ['name'],
  'lastname': ['lastname', 'last', 'surname'],
  'firstname': ['firstname', 'first', 'givenname'],
  'middlename': ['middlename', 'middle'],
  'email': ['email', 'emailaddress'],
  'phonenumber': ['phonenumber', 'phone', 'contactno', 'contact'],
  'category': ['category'],
  'stock': ['stock', 'quantity'],
  'lastupdated': ['lastupdated', 'updatedat', 'updated'],
  'status': ['status'],
  'itemid': ['itemid', 'productid', 'productid'],
  'itemname': ['itemname', 'productname', 'name'],
  'quantity': ['quantity', 'qty'],
  'price': ['price', 'cost', 'amount'],
  'createdat': ['createdat', 'timestamp', 'time', 'date', 'created'],
  'points': ['points', 'score'],
};

/// Returns true if the provided headers (raw list) contain all required canonical fields.
/// `requiredList` should be canonical keys from headerSynonyms (e.g. 'itemid', 'createdat').
List<String> findMissingHeaders(List<String> rawHeaders, List<String> requiredList) {
  final found = rawHeaders.map(normalizeHeader).toSet();
  final missing = <String>[];
  for (final req in requiredList) {
    final synonyms = headerSynonyms[req] ?? [req];
    final ok = synonyms.any((s) => found.contains(s));
    if (!ok) missing.add(req);
  }
  return missing;
}
