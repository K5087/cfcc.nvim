; (namespace_definition
;   name: (_) @name
;   body: (declaration_list) @body)
(namespace_definition
  name: [
    (namespace_identifier) @name
    (nested_namespace_specifier
      (namespace_identifier) @name)+
  ]
  body: (declaration_list) @body)
