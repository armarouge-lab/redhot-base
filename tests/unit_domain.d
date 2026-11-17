// Ring-2 unit tests. Pure, no filesystem, no subprocesses.
module tests.unit_domain;

import domain;

// ---------------------------------------------------------------------------
// parseFlatKeyValue — basic shapes
// ---------------------------------------------------------------------------

unittest
{
    assert(parseFlatKeyValue("").length == 0);
}

unittest
{
    auto pairs = parseFlatKeyValue("# comment\n\n   \n# another\n");
    assert(pairs.length == 0);
}

unittest
{
    auto pairs = parseFlatKeyValue("general.theme=redhot\n");
    assert(pairs.length == 1);
    assert(pairs[0].key == "general.theme");
    assert(pairs[0].value == "redhot");
}

unittest
{
    auto pairs = parseFlatKeyValue("  key  =  value  \n");
    assert(pairs.length == 1);
    assert(pairs[0].key == "key");
    assert(pairs[0].value == "value");
}

// Only the first '=' splits — later '=' stay in the value.
unittest
{
    auto pairs = parseFlatKeyValue("path=/a=b=c\n");
    assert(pairs.length == 1);
    assert(pairs[0].key == "path");
    assert(pairs[0].value == "/a=b=c");
}

// Lines without '=' are silently skipped.
unittest
{
    auto pairs = parseFlatKeyValue("good=ok\nbad line\n");
    assert(pairs.length == 1);
    assert(pairs[0].key == "good");
}

// Empty key is skipped.
unittest
{
    auto pairs = parseFlatKeyValue("=value\n");
    assert(pairs.length == 0);
}

// Empty value is legal.
unittest
{
    auto pairs = parseFlatKeyValue("key=\n");
    assert(pairs.length == 1);
    assert(pairs[0].key == "key");
    assert(pairs[0].value == "");
}

// CRLF line endings.
unittest
{
    auto pairs = parseFlatKeyValue("key=value\r\nother=thing\r\n");
    assert(pairs.length == 2);
    assert(pairs[0].value == "value");
    assert(pairs[1].value == "thing");
}

// Duplicate keys preserved at parse time (last-wins is resolution-time).
unittest
{
    auto pairs = parseFlatKeyValue("k=1\nk=2\nk=3\n");
    assert(pairs.length == 3);
}

// ---------------------------------------------------------------------------
// resolveConfigValue — precedence
// ---------------------------------------------------------------------------

unittest
{
    ConfigPair[] highLayer = [ConfigPair("key", "high")];
    ConfigPair[] lowLayer  = [ConfigPair("key", "low")];
    assert(resolveConfigValue("key", [highLayer, lowLayer]) == "high");
}

unittest
{
    ConfigPair[] highLayer = [ConfigPair("other", "x")];
    ConfigPair[] lowLayer  = [ConfigPair("key", "low")];
    assert(resolveConfigValue("key", [highLayer, lowLayer]) == "low");
}

unittest
{
    ConfigPair[] layer = [
        ConfigPair("key", "first"),
        ConfigPair("key", "second"),
    ];
    assert(resolveConfigValue("key", [layer]) == "second");
}

unittest
{
    ConfigPair[] layer = [ConfigPair("other", "x")];
    assert(resolveConfigValue("key", [layer]) is null);
}

// ---------------------------------------------------------------------------
// expandHomePrefix — pure expansion
// ---------------------------------------------------------------------------

unittest
{
    assert(expandHomePrefix("~/.config", "/home/user") == "/home/user/.config");
}

unittest
{
    assert(expandHomePrefix("~", "/home/user") == "/home/user");
}

unittest
{
    assert(expandHomePrefix("/etc/redhot", "/home/user") == "/etc/redhot");
}

unittest
{
    assert(expandHomePrefix("", "/home/user") == "");
}
