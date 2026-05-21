#define _GNU_SOURCE

#include <ctype.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <libxml/parser.h>
#include <libxml/tree.h>

#include <openssl/evp.h>
#include <openssl/rand.h>

#include <xmlsec/crypto.h>
#include <xmlsec/errors.h>
#include <xmlsec/keys.h>
#include <xmlsec/xmlsec.h>
#include <xmlsec/xmltree.h>
#include <xmlsec/xmldsig.h>
#include <zlib.h>


#define SAML_PROTOCOL_NS "urn:oasis:names:tc:SAML:2.0:protocol"
#define SAML_ASSERTION_NS "urn:oasis:names:tc:SAML:2.0:assertion"
#define DSIG_NS "http://www.w3.org/2000/09/xmldsig#"
#define STATUS_SUCCESS "urn:oasis:names:tc:SAML:2.0:status:Success"


static int xmlsec_initialized = 0;


static void set_err(char *err, size_t err_len, const char *fmt, ...) {
  va_list args;

  if (err == NULL || err_len == 0) {
    return;
  }

  va_start(args, fmt);
  vsnprintf(err, err_len, fmt, args);
  va_end(args);
  err[err_len - 1] = '\0';
}


static int ensure_xmlsec(char *err, size_t err_len) {
  if (xmlsec_initialized) {
    return 0;
  }

  xmlInitParser();

  if (xmlSecInit() < 0) {
    set_err(err, err_len, "xmlsec initialization failed");
    return -1;
  }

  if (xmlSecCheckVersion() != 1) {
    set_err(err, err_len, "xmlsec version mismatch");
    return -1;
  }

  if (xmlSecCryptoAppInit(NULL) < 0) {
    set_err(err, err_len, "xmlsec crypto app initialization failed");
    return -1;
  }

  if (xmlSecCryptoInit() < 0) {
    set_err(err, err_len, "xmlsec crypto initialization failed");
    return -1;
  }

  xmlsec_initialized = 1;
  return 0;
}


static int node_is(xmlNodePtr node, const char *local, const char *ns) {
  if (node == NULL || node->type != XML_ELEMENT_NODE || node->name == NULL) {
    return 0;
  }

  if (xmlStrcmp(node->name, BAD_CAST local) != 0) {
    return 0;
  }

  if (ns == NULL) {
    return 1;
  }

  return node->ns != NULL
      && node->ns->href != NULL
      && xmlStrcmp(node->ns->href, BAD_CAST ns) == 0;
}


static xmlNodePtr first_child(xmlNodePtr parent, const char *local, const char *ns) {
  xmlNodePtr cur;

  if (parent == NULL) {
    return NULL;
  }

  for (cur = parent->children; cur != NULL; cur = cur->next) {
    if (node_is(cur, local, ns)) {
      return cur;
    }
  }

  return NULL;
}


static xmlNodePtr first_descendant(xmlNodePtr parent, const char *local, const char *ns) {
  xmlNodePtr cur;
  xmlNodePtr found;

  if (parent == NULL) {
    return NULL;
  }

  for (cur = parent->children; cur != NULL; cur = cur->next) {
    if (node_is(cur, local, ns)) {
      return cur;
    }

    found = first_descendant(cur, local, ns);
    if (found != NULL) {
      return found;
    }
  }

  return NULL;
}


static int text_equals(xmlNodePtr node, const char *expected) {
  xmlChar *content;
  int rc;

  if (node == NULL || expected == NULL) {
    return 0;
  }

  content = xmlNodeGetContent(node);
  if (content == NULL) {
    return 0;
  }

  rc = xmlStrcmp(content, BAD_CAST expected) == 0;
  xmlFree(content);
  return rc;
}


static int prop_equals(xmlNodePtr node, const char *prop, const char *expected) {
  xmlChar *value;
  int rc;

  if (node == NULL || expected == NULL) {
    return 0;
  }

  value = xmlGetProp(node, BAD_CAST prop);
  if (value == NULL) {
    return 0;
  }

  rc = xmlStrcmp(value, BAD_CAST expected) == 0;
  xmlFree(value);
  return rc;
}


static char *copy_prop(xmlNodePtr node, const char *prop) {
  xmlChar *value;
  char *copy;

  if (node == NULL) {
    return NULL;
  }

  value = xmlGetProp(node, BAD_CAST prop);
  if (value == NULL) {
    return NULL;
  }

  copy = strdup((const char *) value);
  xmlFree(value);
  return copy;
}


static int copy_text_to(xmlNodePtr node, char *out, size_t out_len) {
  xmlChar *content;

  if (out == NULL || out_len == 0) {
    return -1;
  }

  out[0] = '\0';

  if (node == NULL) {
    return 0;
  }

  content = xmlNodeGetContent(node);
  if (content == NULL) {
    return 0;
  }

  snprintf(out, out_len, "%s", (const char *) content);
  out[out_len - 1] = '\0';
  xmlFree(content);
  return 0;
}


static int copy_string_to(const char *value, char *out, size_t out_len) {
  if (out == NULL || out_len == 0) {
    return -1;
  }

  if (value == NULL) {
    out[0] = '\0';
    return 0;
  }

  snprintf(out, out_len, "%s", value);
  out[out_len - 1] = '\0';
  return 0;
}


static int parse_saml_time(const char *value, time_t *out) {
  struct tm tm_value;
  const char *cursor;
  int year;
  int month;
  int day;
  int hour;
  int minute;
  int second;

  if (value == NULL || out == NULL) {
    return -1;
  }

  if (sscanf(value, "%4d-%2d-%2dT%2d:%2d:%2d",
        &year, &month, &day, &hour, &minute, &second) != 6) {
    return -1;
  }

  cursor = value + 19;
  if (*cursor == '.') {
    cursor++;
    while (isdigit((unsigned char) *cursor)) {
      cursor++;
    }
  }

  if (*cursor != 'Z' || *(cursor + 1) != '\0') {
    return -1;
  }

  memset(&tm_value, 0, sizeof(tm_value));
  tm_value.tm_year = year - 1900;
  tm_value.tm_mon = month - 1;
  tm_value.tm_mday = day;
  tm_value.tm_hour = hour;
  tm_value.tm_min = minute;
  tm_value.tm_sec = second;
  tm_value.tm_isdst = 0;

  *out = timegm(&tm_value);
  return *out == (time_t) -1 ? -1 : 0;
}


static int check_time_prop(xmlNodePtr node, const char *prop, time_t now, int skew,
    int not_before, char *err, size_t err_len) {
  xmlChar *raw;
  time_t parsed;

  raw = xmlGetProp(node, BAD_CAST prop);
  if (raw == NULL) {
    return 0;
  }

  if (parse_saml_time((const char *) raw, &parsed) != 0) {
    set_err(err, err_len, "invalid SAML time in %s", prop);
    xmlFree(raw);
    return -1;
  }

  xmlFree(raw);

  if (not_before) {
    if ((now + skew) < parsed) {
      set_err(err, err_len, "SAML assertion is not yet valid");
      return -1;
    }
  } else {
    if ((now - skew) >= parsed) {
      set_err(err, err_len, "SAML assertion has expired");
      return -1;
    }
  }

  return 0;
}


static int reference_uri_matches(xmlNodePtr signature, const char *id) {
  xmlNodePtr signed_info;
  xmlNodePtr reference;
  xmlNodePtr cur;
  xmlChar *uri;
  char expected[1024];
  int rc;
  int references = 0;

  if (signature == NULL || id == NULL || id[0] == '\0') {
    return 0;
  }

  signed_info = first_child(signature, "SignedInfo", DSIG_NS);
  if (signed_info == NULL) {
    return 0;
  }

  reference = NULL;
  for (cur = signed_info->children; cur != NULL; cur = cur->next) {
    if (node_is(cur, "Reference", DSIG_NS)) {
      references++;
      reference = cur;
    }
  }

  if (references != 1 || reference == NULL) {
    return 0;
  }

  uri = xmlGetProp(reference, BAD_CAST "URI");
  if (uri == NULL) {
    return 0;
  }

  snprintf(expected, sizeof(expected), "#%s", id);
  expected[sizeof(expected) - 1] = '\0';
  rc = xmlStrcmp(uri, BAD_CAST expected) == 0;
  xmlFree(uri);
  return rc;
}


static int verify_signature(xmlDocPtr doc, xmlNodePtr signed_node, xmlNodePtr signature,
    const char *cert_pem, size_t cert_len, char *err, size_t err_len) {
  xmlSecDSigCtxPtr dsig_ctx = NULL;
  xmlSecKeyPtr key = NULL;
  char *signed_id = NULL;
  int rc = -1;

  signed_id = copy_prop(signed_node, "ID");
  if (signed_id == NULL || signed_id[0] == '\0') {
    set_err(err, err_len, "signed SAML node is missing ID");
    goto done;
  }

  if (!reference_uri_matches(signature, signed_id)) {
    set_err(err, err_len, "SAML signature reference did not match signed node ID");
    goto done;
  }

  key = xmlSecCryptoAppKeyLoadMemory((const xmlSecByte *) cert_pem,
      (xmlSecSize) cert_len,
      xmlSecKeyDataFormatCertPem,
      NULL,
      NULL,
      NULL);
  if (key == NULL) {
    set_err(err, err_len, "could not load IdP certificate for signature validation");
    goto done;
  }

  dsig_ctx = xmlSecDSigCtxCreate(NULL);
  if (dsig_ctx == NULL) {
    set_err(err, err_len, "could not create XML signature context");
    goto done;
  }

  dsig_ctx->signKey = key;
  key = NULL;

  if (xmlSecDSigCtxVerify(dsig_ctx, signature) < 0) {
    set_err(err, err_len, "XML signature verification failed");
    goto done;
  }

  if (dsig_ctx->status != xmlSecDSigStatusSucceeded) {
    set_err(err, err_len, "XML signature was not valid");
    goto done;
  }

  (void) doc;
  rc = 0;

done:
  if (key != NULL) {
    xmlSecKeyDestroy(key);
  }
  if (dsig_ctx != NULL) {
    xmlSecDSigCtxDestroy(dsig_ctx);
  }
  free(signed_id);
  return rc;
}


static int check_status(xmlNodePtr response, char *err, size_t err_len) {
  xmlNodePtr status;
  xmlNodePtr code;
  xmlChar *value;
  int rc;

  status = first_child(response, "Status", SAML_PROTOCOL_NS);
  code = first_child(status, "StatusCode", SAML_PROTOCOL_NS);
  if (code == NULL) {
    set_err(err, err_len, "SAML Response did not contain a StatusCode");
    return -1;
  }

  value = xmlGetProp(code, BAD_CAST "Value");
  if (value == NULL) {
    set_err(err, err_len, "SAML StatusCode did not contain a Value");
    return -1;
  }

  rc = xmlStrcmp(value, BAD_CAST STATUS_SUCCESS) == 0;
  xmlFree(value);

  if (!rc) {
    set_err(err, err_len, "SAML Response status was not Success");
    return -1;
  }

  return 0;
}


static int check_conditions(xmlNodePtr assertion, const char *expected_audience,
    time_t now, int skew, char *err, size_t err_len) {
  xmlNodePtr conditions;
  xmlNodePtr cur;
  int audience_ok = 0;

  conditions = first_child(assertion, "Conditions", SAML_ASSERTION_NS);
  if (conditions == NULL) {
    set_err(err, err_len, "SAML Assertion did not contain Conditions");
    return -1;
  }

  if (check_time_prop(conditions, "NotBefore", now, skew, 1, err, err_len) != 0) {
    return -1;
  }

  if (check_time_prop(conditions, "NotOnOrAfter", now, skew, 0, err, err_len) != 0) {
    return -1;
  }

  for (cur = conditions->children; cur != NULL; cur = cur->next) {
    xmlNodePtr audience;

    if (!node_is(cur, "AudienceRestriction", SAML_ASSERTION_NS)) {
      continue;
    }

    for (audience = cur->children; audience != NULL; audience = audience->next) {
      if (node_is(audience, "Audience", SAML_ASSERTION_NS)
          && text_equals(audience, expected_audience)) {
        audience_ok = 1;
        break;
      }
    }
  }

  if (!audience_ok) {
    set_err(err, err_len, "SAML Assertion audience did not match the SP entity ID");
    return -1;
  }

  return 0;
}


static int check_subject_confirmation(xmlNodePtr assertion, const char *expected_recipient,
    time_t now, int skew, char *err, size_t err_len) {
  xmlNodePtr subject;
  xmlNodePtr confirmation;

  subject = first_child(assertion, "Subject", SAML_ASSERTION_NS);
  if (subject == NULL) {
    set_err(err, err_len, "SAML Assertion did not contain Subject");
    return -1;
  }

  for (confirmation = subject->children; confirmation != NULL; confirmation = confirmation->next) {
    xmlNodePtr data;

    if (!node_is(confirmation, "SubjectConfirmation", SAML_ASSERTION_NS)) {
      continue;
    }

    data = first_child(confirmation, "SubjectConfirmationData", SAML_ASSERTION_NS);
    if (data == NULL) {
      continue;
    }

    if (!prop_equals(data, "Recipient", expected_recipient)) {
      continue;
    }

    if (check_time_prop(data, "NotOnOrAfter", now, skew, 0, err, err_len) != 0) {
      return -1;
    }

    return 0;
  }

  set_err(err, err_len, "SAML SubjectConfirmation recipient did not match the ACS URL");
  return -1;
}


static xmlDocPtr parse_saml_xml(const char *xml, size_t xml_len, char *err, size_t err_len) {
  xmlDocPtr doc;
  const xmlChar *id_attrs[] = {
    BAD_CAST "ID",
    NULL,
  };

  doc = xmlReadMemory(xml,
      (int) xml_len,
      "saml-response.xml",
      NULL,
      XML_PARSE_NONET | XML_PARSE_NOERROR | XML_PARSE_NOWARNING);
  if (doc == NULL) {
    set_err(err, err_len, "could not parse SAML XML");
    return NULL;
  }

  xmlSecAddIDs(doc, xmlDocGetRootElement(doc), id_attrs);
  return doc;
}


int kong_saml_random(unsigned char *out, size_t out_len, char *err, size_t err_len) {
  if (out == NULL) {
    set_err(err, err_len, "random output buffer was null");
    return -1;
  }

  if (RAND_bytes(out, (int) out_len) != 1) {
    set_err(err, err_len, "OpenSSL RAND_bytes failed");
    return -1;
  }

  return 0;
}


int kong_saml_deflate_raw(const unsigned char *input, size_t input_len,
    unsigned char *output, size_t output_len, size_t *actual_out_len,
    char *err, size_t err_len) {
  z_stream stream;
  int rc;

  if (input == NULL || output == NULL || actual_out_len == NULL) {
    set_err(err, err_len, "deflate input, output, and length pointers are required");
    return -1;
  }

  memset(&stream, 0, sizeof(stream));
  stream.next_in = (Bytef *) input;
  stream.avail_in = (uInt) input_len;
  stream.next_out = output;
  stream.avail_out = (uInt) output_len;

  rc = deflateInit2(&stream,
      Z_BEST_COMPRESSION,
      Z_DEFLATED,
      -MAX_WBITS,
      8,
      Z_DEFAULT_STRATEGY);
  if (rc != Z_OK) {
    set_err(err, err_len, "could not initialize raw DEFLATE");
    return -1;
  }

  rc = deflate(&stream, Z_FINISH);
  if (rc != Z_STREAM_END) {
    deflateEnd(&stream);
    set_err(err, err_len, "raw DEFLATE failed or output buffer was too small");
    return -1;
  }

  *actual_out_len = stream.total_out;
  deflateEnd(&stream);
  return 0;
}


int kong_saml_aes_gcm_encrypt(const unsigned char *key, size_t key_len,
    const unsigned char *iv, size_t iv_len,
    const unsigned char *aad, size_t aad_len,
    const unsigned char *plaintext, size_t plaintext_len,
    unsigned char *ciphertext,
    unsigned char *tag, size_t tag_len,
    char *err, size_t err_len) {
  EVP_CIPHER_CTX *ctx = NULL;
  int out_len = 0;
  int total_len = 0;
  int rc = -1;

  if (key_len != 32 || iv_len != 12 || tag_len != 16) {
    set_err(err, err_len, "AES-GCM requires a 32 byte key, 12 byte IV, and 16 byte tag");
    return -1;
  }

  ctx = EVP_CIPHER_CTX_new();
  if (ctx == NULL) {
    set_err(err, err_len, "could not create OpenSSL cipher context");
    return -1;
  }

  if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1
      || EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int) iv_len, NULL) != 1
      || EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv) != 1) {
    set_err(err, err_len, "could not initialize AES-GCM encryption");
    goto done;
  }

  if (aad_len > 0
      && EVP_EncryptUpdate(ctx, NULL, &out_len, aad, (int) aad_len) != 1) {
    set_err(err, err_len, "could not authenticate AES-GCM AAD");
    goto done;
  }

  if (plaintext_len > 0
      && EVP_EncryptUpdate(ctx, ciphertext, &out_len, plaintext, (int) plaintext_len) != 1) {
    set_err(err, err_len, "could not encrypt AES-GCM payload");
    goto done;
  }
  total_len = out_len;

  if (EVP_EncryptFinal_ex(ctx, ciphertext + total_len, &out_len) != 1) {
    set_err(err, err_len, "could not finalize AES-GCM encryption");
    goto done;
  }
  total_len += out_len;

  if ((size_t) total_len != plaintext_len) {
    set_err(err, err_len, "AES-GCM ciphertext length mismatch");
    goto done;
  }

  if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, (int) tag_len, tag) != 1) {
    set_err(err, err_len, "could not read AES-GCM tag");
    goto done;
  }

  rc = 0;

done:
  EVP_CIPHER_CTX_free(ctx);
  return rc;
}


int kong_saml_aes_gcm_decrypt(const unsigned char *key, size_t key_len,
    const unsigned char *iv, size_t iv_len,
    const unsigned char *aad, size_t aad_len,
    const unsigned char *ciphertext, size_t ciphertext_len,
    const unsigned char *tag, size_t tag_len,
    unsigned char *plaintext,
    char *err, size_t err_len) {
  EVP_CIPHER_CTX *ctx = NULL;
  int out_len = 0;
  int total_len = 0;
  int rc = -1;

  if (key_len != 32 || iv_len != 12 || tag_len != 16) {
    set_err(err, err_len, "AES-GCM requires a 32 byte key, 12 byte IV, and 16 byte tag");
    return -1;
  }

  ctx = EVP_CIPHER_CTX_new();
  if (ctx == NULL) {
    set_err(err, err_len, "could not create OpenSSL cipher context");
    return -1;
  }

  if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1
      || EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int) iv_len, NULL) != 1
      || EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv) != 1) {
    set_err(err, err_len, "could not initialize AES-GCM decryption");
    goto done;
  }

  if (aad_len > 0
      && EVP_DecryptUpdate(ctx, NULL, &out_len, aad, (int) aad_len) != 1) {
    set_err(err, err_len, "could not authenticate AES-GCM AAD");
    goto done;
  }

  if (ciphertext_len > 0
      && EVP_DecryptUpdate(ctx, plaintext, &out_len, ciphertext, (int) ciphertext_len) != 1) {
    set_err(err, err_len, "could not decrypt AES-GCM payload");
    goto done;
  }
  total_len = out_len;

  if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, (int) tag_len, (void *) tag) != 1) {
    set_err(err, err_len, "could not set AES-GCM tag");
    goto done;
  }

  if (EVP_DecryptFinal_ex(ctx, plaintext + total_len, &out_len) != 1) {
    set_err(err, err_len, "AES-GCM authentication failed");
    goto done;
  }
  total_len += out_len;

  if ((size_t) total_len != ciphertext_len) {
    set_err(err, err_len, "AES-GCM plaintext length mismatch");
    goto done;
  }

  rc = 0;

done:
  EVP_CIPHER_CTX_free(ctx);
  return rc;
}


int kong_saml_validate_response(const char *xml, size_t xml_len,
    const char *cert_pem, size_t cert_len,
    const char *expected_issuer,
    const char *expected_audience,
    const char *expected_destination,
    const char *expected_recipient,
    long now,
    int skew,
    char *err,
    size_t err_len) {
  xmlDocPtr doc = NULL;
  xmlNodePtr response;
  xmlNodePtr response_signature;
  xmlNodePtr assertion;
  xmlNodePtr assertion_signature;
  xmlNodePtr issuer;
  time_t now_time = (time_t) now;
  int rc = -1;

  if (xml == NULL || cert_pem == NULL) {
    set_err(err, err_len, "SAML XML and certificate are required");
    return -1;
  }

  if (ensure_xmlsec(err, err_len) != 0) {
    return -1;
  }

  doc = parse_saml_xml(xml, xml_len, err, err_len);
  if (doc == NULL) {
    return -1;
  }

  response = xmlDocGetRootElement(doc);
  if (!node_is(response, "Response", SAML_PROTOCOL_NS)) {
    set_err(err, err_len, "SAML document root was not a Response");
    goto done;
  }

  if (!prop_equals(response, "Destination", expected_destination)) {
    set_err(err, err_len, "SAML Response destination did not match the ACS URL");
    goto done;
  }

  issuer = first_child(response, "Issuer", SAML_ASSERTION_NS);
  if (!text_equals(issuer, expected_issuer)) {
    set_err(err, err_len, "SAML Response issuer did not match the IdP entity ID");
    goto done;
  }

  if (check_status(response, err, err_len) != 0) {
    goto done;
  }

  assertion = first_child(response, "Assertion", SAML_ASSERTION_NS);
  if (assertion == NULL) {
    set_err(err, err_len, "SAML Response did not contain an Assertion");
    goto done;
  }

  response_signature = first_child(response, "Signature", DSIG_NS);
  if (response_signature == NULL) {
    set_err(err, err_len, "SAML Response was not signed");
    goto done;
  }

  assertion_signature = first_child(assertion, "Signature", DSIG_NS);
  if (assertion_signature == NULL) {
    set_err(err, err_len, "SAML Assertion was not signed");
    goto done;
  }

  if (verify_signature(doc, response, response_signature, cert_pem, cert_len, err, err_len) != 0) {
    goto done;
  }

  if (verify_signature(doc, assertion, assertion_signature, cert_pem, cert_len, err, err_len) != 0) {
    goto done;
  }

  if (check_conditions(assertion, expected_audience, now_time, skew, err, err_len) != 0) {
    goto done;
  }

  if (check_subject_confirmation(assertion, expected_recipient, now_time, skew, err, err_len) != 0) {
    goto done;
  }

  rc = 0;

done:
  if (doc != NULL) {
    xmlFreeDoc(doc);
  }
  return rc;
}


int kong_saml_extract(const char *xml, size_t xml_len,
    const char *selector,
    const char *name,
    char *out,
    size_t out_len,
    char *err,
    size_t err_len) {
  xmlDocPtr doc = NULL;
  xmlNodePtr response;
  xmlNodePtr assertion;
  int rc = -1;

  if (out == NULL || out_len == 0) {
    set_err(err, err_len, "output buffer is required");
    return -1;
  }
  out[0] = '\0';

  if (xml == NULL || selector == NULL) {
    set_err(err, err_len, "SAML XML and selector are required");
    return -1;
  }

  doc = parse_saml_xml(xml, xml_len, err, err_len);
  if (doc == NULL) {
    return -1;
  }

  response = xmlDocGetRootElement(doc);
  assertion = first_child(response, "Assertion", SAML_ASSERTION_NS);

  if (strcmp(selector, "response_in_response_to") == 0) {
    char *value = copy_prop(response, "InResponseTo");
    rc = copy_string_to(value, out, out_len);
    free(value);
    goto done;
  }

  if (strcmp(selector, "assertion_id") == 0) {
    char *value = copy_prop(assertion, "ID");
    rc = copy_string_to(value, out, out_len);
    free(value);
    goto done;
  }

  if (strcmp(selector, "nameid") == 0) {
    xmlNodePtr subject = first_child(assertion, "Subject", SAML_ASSERTION_NS);
    xmlNodePtr name_id = first_descendant(subject, "NameID", SAML_ASSERTION_NS);
    rc = copy_text_to(name_id, out, out_len);
    goto done;
  }

  if (strcmp(selector, "attribute") == 0) {
    xmlNodePtr statements;
    xmlNodePtr statement;

    if (name == NULL || name[0] == '\0') {
      set_err(err, err_len, "attribute selector requires a SAML attribute name");
      goto done;
    }

    statements = assertion;
    for (statement = statements != NULL ? statements->children : NULL;
         statement != NULL;
         statement = statement->next) {
      xmlNodePtr attribute;

      if (!node_is(statement, "AttributeStatement", SAML_ASSERTION_NS)) {
        continue;
      }

      for (attribute = statement->children; attribute != NULL; attribute = attribute->next) {
        xmlChar *attr_name;

        if (!node_is(attribute, "Attribute", SAML_ASSERTION_NS)) {
          continue;
        }

        attr_name = xmlGetProp(attribute, BAD_CAST "Name");
        if (attr_name == NULL) {
          continue;
        }

        if (xmlStrcmp(attr_name, BAD_CAST name) == 0) {
          xmlNodePtr value = first_child(attribute, "AttributeValue", SAML_ASSERTION_NS);
          xmlFree(attr_name);
          rc = copy_text_to(value, out, out_len);
          goto done;
        }

        xmlFree(attr_name);
      }
    }

    rc = 0;
    goto done;
  }

  set_err(err, err_len, "unknown SAML extraction selector");

done:
  if (doc != NULL) {
    xmlFreeDoc(doc);
  }
  return rc;
}
