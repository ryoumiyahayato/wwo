#!/usr/bin/env python3
"""Small, dependency-free JSON Schema 2020-12 execution path.

The source-pack validators run in repository and CI environments where adding
an unpinned network dependency is not acceptable. This module implements the
JSON Schema keywords used by the tracked Batch 1-4 schemas, including local
refs/defs resolution, object-property closure, nested arrays and objects,
type/enum/const constraints, date/URI formats, and numeric/string bounds.
Unsupported assertion keywords are reported instead of ignored.
"""

from __future__ import annotations

import copy
import re
from datetime import date
from typing import Any
from urllib.parse import urlparse


SUPPORTED_ASSERTION_KEYWORDS = {
    "$defs",
    "$id",
    "$ref",
    "$schema",
    "additionalProperties",
    "allOf",
    "anyOf",
    "const",
    "enum",
    "exclusiveMaximum",
    "exclusiveMinimum",
    "format",
    "items",
    "maxItems",
    "maxLength",
    "maximum",
    "minItems",
    "minLength",
    "minimum",
    "not",
    "oneOf",
    "pattern",
    "properties",
    "required",
    "type",
    "uniqueItems",
}

ANNOTATION_KEYWORDS = {
    "default",
    "description",
    "examples",
    "readOnly",
    "title",
    "deprecated",
    "writeOnly",
}


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _json_type_matches(value: Any, expected: str) -> bool:
    if expected == "null":
        return value is None
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "number":
        return _is_number(value)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    return False


def _pointer_get(document: Any, pointer: str) -> Any:
    if pointer == "":
        return document
    if not pointer.startswith("/"):
        raise KeyError(pointer)
    current = document
    for token in pointer[1:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        if isinstance(current, list):
            current = current[int(token)]
        else:
            current = current[token]
    return current


def schema_structure_errors(schema: Any, path: str = "$") -> list[str]:
    """Reject assertion keywords that this explicit local path cannot execute."""

    errors: list[str] = []
    if isinstance(schema, bool):
        return errors
    if not isinstance(schema, dict):
        return [f"{path}: schema must be an object or boolean"]
    for keyword in schema:
        if keyword not in SUPPORTED_ASSERTION_KEYWORDS and keyword not in ANNOTATION_KEYWORDS:
            errors.append(f"{path}: unsupported JSON Schema keyword {keyword!r}")
    for key in ("properties", "$defs"):
        value = schema.get(key)
        if isinstance(value, dict):
            for name, child in value.items():
                errors.extend(schema_structure_errors(child, f"{path}.{key}.{name}"))
    for key in ("items", "additionalProperties", "not"):
        if key in schema and isinstance(schema[key], (dict, bool)):
            errors.extend(schema_structure_errors(schema[key], f"{path}.{key}"))
    for key in ("allOf", "anyOf", "oneOf"):
        value = schema.get(key)
        if isinstance(value, list):
            for index, child in enumerate(value):
                errors.extend(schema_structure_errors(child, f"{path}.{key}[{index}]"))
    return errors


def _format_error(value: Any, fmt: str) -> str | None:
    if not isinstance(value, str):
        return None
    if fmt == "date":
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            return "must be an ISO date"
        try:
            date.fromisoformat(value)
        except ValueError:
            return "must be a valid ISO date"
        return None
    if fmt == "uri":
        parsed = urlparse(value)
        if not parsed.scheme or any(character.isspace() for character in value):
            return "must be an absolute URI"
        return None
    if fmt == "uri-reference":
        if any(character.isspace() for character in value):
            return "must be a URI reference without whitespace"
        return None
    return f"unsupported format {fmt!r}"


def validate_instance(instance: Any, schema: Any, *, path: str = "$") -> list[str]:
    """Return all validation errors for one instance/schema pair."""

    root_schema = schema

    def walk(value: Any, current_schema: Any, current_path: str, root: Any) -> list[str]:
        if current_schema is True:
            return []
        if current_schema is False:
            return [f"{current_path}: schema is false"]
        if not isinstance(current_schema, dict):
            return [f"{current_path}: schema must be an object or boolean"]

        if "$ref" in current_schema:
            reference = current_schema["$ref"]
            if not isinstance(reference, str) or not reference.startswith("#"):
                return [f"{current_path}: only local JSON Schema references are supported: {reference!r}"]
            try:
                referenced = _pointer_get(root, reference[1:])
            except (KeyError, IndexError, ValueError, TypeError) as exc:
                return [f"{current_path}: unresolved JSON Schema reference {reference!r}: {exc}"]
            return walk(value, referenced, current_path, root)

        errors: list[str] = []
        for composition in ("allOf", "anyOf", "oneOf"):
            if composition not in current_schema:
                continue
            branches = current_schema[composition]
            if not isinstance(branches, list):
                errors.append(f"{current_path}.{composition}: must be an array")
                continue
            branch_errors = [walk(value, branch, current_path, root) for branch in branches]
            valid_count = sum(not branch_error for branch_error in branch_errors)
            if composition == "allOf" and valid_count != len(branches):
                errors.append(f"{current_path}: allOf constraint failed")
            elif composition == "anyOf" and valid_count == 0:
                errors.append(f"{current_path}: anyOf constraint failed")
            elif composition == "oneOf" and valid_count != 1:
                errors.append(f"{current_path}: oneOf constraint failed")

        if "not" in current_schema and not walk(value, current_schema["not"], current_path, root):
            errors.append(f"{current_path}: not constraint failed")

        if "const" in current_schema and value != current_schema["const"]:
            errors.append(f"{current_path}: expected const {current_schema['const']!r}, found {value!r}")
        if "enum" in current_schema:
            allowed = current_schema["enum"]
            if not isinstance(allowed, list) or not any(value == candidate for candidate in allowed):
                errors.append(f"{current_path}: value {value!r} is not in enum {allowed!r}")

        if "type" in current_schema:
            expected_types = current_schema["type"]
            if isinstance(expected_types, str):
                expected_types = [expected_types]
            if not isinstance(expected_types, list) or not any(
                isinstance(item, str) and _json_type_matches(value, item) for item in expected_types
            ):
                errors.append(f"{current_path}: expected JSON type {expected_types!r}, found {type(value).__name__}")
                return errors

        if "format" in current_schema:
            format_error = _format_error(value, current_schema["format"])
            if format_error:
                errors.append(f"{current_path}: {format_error}")
        if isinstance(value, str):
            if "minLength" in current_schema and len(value) < current_schema["minLength"]:
                errors.append(f"{current_path}: length is below minLength")
            if "maxLength" in current_schema and len(value) > current_schema["maxLength"]:
                errors.append(f"{current_path}: length exceeds maxLength")
            if "pattern" in current_schema:
                try:
                    matches = re.search(current_schema["pattern"], value)
                except re.error as exc:
                    errors.append(f"{current_path}: invalid schema pattern: {exc}")
                    matches = True
                if not matches:
                    errors.append(f"{current_path}: does not match pattern {current_schema['pattern']!r}")

        if _is_number(value):
            if "minimum" in current_schema and value < current_schema["minimum"]:
                errors.append(f"{current_path}: is below minimum")
            if "maximum" in current_schema and value > current_schema["maximum"]:
                errors.append(f"{current_path}: exceeds maximum")
            if "exclusiveMinimum" in current_schema:
                limit = current_schema["exclusiveMinimum"]
                if isinstance(limit, bool) or value <= limit:
                    errors.append(f"{current_path}: is not above exclusiveMinimum")
            if "exclusiveMaximum" in current_schema:
                limit = current_schema["exclusiveMaximum"]
                if isinstance(limit, bool) or value >= limit:
                    errors.append(f"{current_path}: is not below exclusiveMaximum")

        if isinstance(value, list):
            if "minItems" in current_schema and len(value) < current_schema["minItems"]:
                errors.append(f"{current_path}: item count is below minItems")
            if "maxItems" in current_schema and len(value) > current_schema["maxItems"]:
                errors.append(f"{current_path}: item count exceeds maxItems")
            if current_schema.get("uniqueItems") is True:
                for index, item in enumerate(value):
                    if any(item == previous for previous in value[:index]):
                        errors.append(f"{current_path}[{index}]: duplicate item violates uniqueItems")
                        break
            if "items" in current_schema:
                for index, item in enumerate(value):
                    errors.extend(walk(item, current_schema["items"], f"{current_path}[{index}]", root))

        if isinstance(value, dict):
            properties = current_schema.get("properties", {})
            if not isinstance(properties, dict):
                errors.append(f"{current_path}.properties: must be an object")
                properties = {}
            required = current_schema.get("required", [])
            if not isinstance(required, list):
                errors.append(f"{current_path}.required: must be an array")
                required = []
            for name in required:
                if name not in value:
                    errors.append(f"{current_path}: missing required property {name!r}")
            for name, property_schema in properties.items():
                if name in value:
                    errors.extend(walk(value[name], property_schema, f"{current_path}.{name}", root))
            additional = current_schema.get("additionalProperties", True)
            for name, property_value in value.items():
                if name in properties:
                    continue
                if additional is False:
                    errors.append(f"{current_path}: unknown property {name!r} is rejected by additionalProperties=false")
                elif isinstance(additional, (dict, bool)):
                    errors.extend(walk(property_value, additional, f"{current_path}.{name}", root))

        return errors

    return walk(instance, copy.deepcopy(schema), path, root_schema)


def validate_json_document(instance: Any, schema: Any) -> list[str]:
    """Validate a document and fail closed if the schema has unsupported pieces."""

    structure_errors = schema_structure_errors(schema)
    if structure_errors:
        return structure_errors
    return validate_instance(instance, schema)
