defmodule Gollum.HostTest do
  use ExUnit.Case, async: true
  alias Gollum.Host
  doctest Gollum.Host

  test "which_agent/2" do
    agents = ~w(googlebot-news * googlebot)
    assert Host.which_agent(agents, "Googlebot-News") == "googlebot-news"
    assert Host.which_agent(agents, "Googlebot") == "googlebot"
    assert Host.which_agent(agents, "Googlebot-Image") == "googlebot"
    assert Host.which_agent(agents, "Otherbot") == "*"
  end

  test "match_agent?/2" do
    assert Host.match_agent?("Hello", "He")
    refute Host.match_agent?("Hello", "Helloo")
  end

  test "match_path?/2" do
    assert Host.match_path?("/anyValidURL", "/")
    assert Host.match_path?("/anyValidURL", "/*")
    assert Host.match_path?("/fish.html", "/fish")
    assert Host.match_path?("/fish/salmon.html", "/fish*")
    assert Host.match_path?("/fish/", "/fish/")
    assert Host.match_path?("/filename.php", "/*.php")
    assert Host.match_path?("/folder/filename.php", "/*.php$")
    assert Host.match_path?("/fishheads/catfish.php?parameters", "/fish*.php")
    refute Host.match_path?("/fish", "/fish/")
    refute Host.match_path?("/", "/*.php")
    refute Host.match_path?("/filename.php?params", "/*.php$")
    refute Host.match_path?("/Fish.PHP", "/fish*.php")
    refute Host.match_path?("/Fish.asp", "/fish")
    refute Host.match_path?("/catfish", "/fish*")
  end

  describe "crawlable?/3" do
    # Rules are colon separated name-value pairs. The following names are
    # provisioned:
    #     user-agent: <value>
    #     allow: <value>
    #     disallow: <value>
    # See REP RFC section "Protocol Definition".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.1
    test "handles rules" do
      path = "/x/y"

      with robotstxt <- ~s"""
           user-agent: FooBot
           disallow: /
           """,
           rules <- Gollum.Parser.parse(robotstxt),
           host <- Host.new("http://foo.bar", rules) do
        # Correct
        refute Host.crawlable?(host, "FooBot", path) == :crawlable
      end

      with robotstxt <- ~s"""
           foo: FooBot
           bar: /
           """,
           rules <- Gollum.Parser.parse(robotstxt),
           host <- Host.new("http://foo.bar", rules) do
        # Incorrect
        assert Host.crawlable?(host, "FooBot", path) == :undefined
      end
    end

    # A group is one or more user-agent line followed by rules, and terminated
    # by a another user-agent line. Rules for same user-agents are combined
    # opaquely into one group. Rules outside groups are ignored.
    # See REP RFC section "Protocol Definition".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.1
    test "handles groups" do
      robotstxt = ~s"""
      allow: /foo/bar/

      user-agent: FooBot
      disallow: /
      allow: /x/
      user-agent: BarBot
      disallow: /
      allow: /y/


      allow: /w/
      user-agent: BazBot

      user-agent: FooBot
      allow: /z/
      disallow /
      """

      rules = Gollum.Parser.parse(robotstxt)
      host = Host.new("http://foo.bar", rules)
      path_w = "/w/a"
      path_x = "/x/b"
      path_y = "/y/c"
      path_z = "/z/d"
      path_foo = "/foo/bar/"

      assert Host.crawlable?(host, "FooBot", path_x) == :crawlable
      assert Host.crawlable?(host, "FooBot", path_z) == :crawlable
      refute Host.crawlable?(host, "FooBot", path_y) == :crawlable
      assert Host.crawlable?(host, "BarBot", path_y) == :crawlable
      assert Host.crawlable?(host, "BarBot", path_w) == :crawlable
      refute Host.crawlable?(host, "BarBot", path_z) == :crawlable
      assert Host.crawlable?(host, "BazBot", path_z) == :crawlable

      # Lines with rules outside groups are ignored.
      refute Host.crawlable?(host, "FooBot", path_foo) == :crawlable
      refute Host.crawlable?(host, "BarBot", path_foo) == :crawlable
      refute Host.crawlable?(host, "BazBot", path_foo) == :crawlable
    end

    # Group must not be closed by rules not explicitly defined in the REP RFC.
    # See REP RFC section "Protocol Definition".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.1
    test "handles closing of groups" do
      path = "/"

      with robotstxt <- ~s"""
           User-Agent: BarBot
           Sitemap: https://foo.bar/sitemap
           User-Agent: *
           Disallow: /
           """,
           rules = Gollum.Parser.parse(robotstxt),
           host = Host.new("http://foo.bar/", rules) do
        refute Host.crawlable?(host, "FooBot", path) == :crawlable
        refute Host.crawlable?(host, "BarBot", path) == :crawlable
      end

      with robotstxt <- ~s"""
           User-Agent: FooBot
           Invalid-Unknown-Line: unknown
           User-Agent: *
           Disallow: /
           """,
           rules = Gollum.Parser.parse(robotstxt),
           host = Host.new("http://foo.bar/", rules) do
        refute Host.crawlable?(host, "FooBot", path) == :crawlable
        refute Host.crawlable?(host, "BarBot", path) == :crawlable
      end
    end

    # REP lines are case insensitive. See REP RFC section "Protocol Definition".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.1
    test "treats keys case insensitive" do
      robotstxt_upper = ~s"""
      USER-AGENT: FooBot
      ALLOW: /x/
      Disallow: /
      """

      robotstxt_lower = ~s"""
      user-agent: FooBot
      allow: /x/
      disallow: /
      """

      robotstxt_camel = ~s"""
      uSeR-aGeNt: FooBot
      AlLoW: /x/
      dIsAlLoW: /
      """

      host_upper =
        Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt_upper))

      host_lower =
        Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt_lower))

      host_camel =
        Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt_camel))

      path_allowed = "/x/y"
      path_disallowed = "/a/b"

      assert Host.crawlable?(host_upper, "FooBot", path_allowed) == :crawlable
      assert Host.crawlable?(host_lower, "FooBot", path_allowed) == :crawlable
      assert Host.crawlable?(host_camel, "FooBot", path_allowed) == :crawlable

      refute Host.crawlable?(host_upper, "FooBot", path_disallowed) ==
               :crawlable

      refute Host.crawlable?(host_lower, "FooBot", path_disallowed) ==
               :crawlable

      refute Host.crawlable?(host_camel, "FooBot", path_disallowed) ==
               :crawlable
    end

    # User-agent line values are case insensitive. See REP RFC section "The
    # user-agent line".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.2.1
    test "treats user-agent values case insensitive" do
      robotstxt_upper = ~s"""
      User-Agent: FOO BAR
      Allow: /x/
      Disallow: /
      """

      robotstxt_lower = ~s"""
      User-Agent: foo bar
      Allow: /x/
      Disallow: /
      """

      robotstxt_camel = ~s"""
      User-Agent: FoO bAr
      Allow: /x/
      Disallow: /
      """

      host_upper =
        Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt_upper))

      host_lower =
        Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt_lower))

      host_camel =
        Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt_camel))

      path_allowed = "/x/y"
      path_disallowed = "/a/b"

      assert Host.crawlable?(host_upper, "Foo Bar", path_allowed) == :crawlable
      assert Host.crawlable?(host_lower, "Foo Bar", path_allowed) == :crawlable
      assert Host.crawlable?(host_camel, "Foo Bar", path_allowed) == :crawlable

      refute Host.crawlable?(host_upper, "Foo Bar", path_disallowed) ==
               :crawlable

      refute Host.crawlable?(host_lower, "Foo Bar", path_disallowed) ==
               :crawlable

      refute Host.crawlable?(host_camel, "Foo Bar", path_disallowed) ==
               :crawlable

      assert Host.crawlable?(host_upper, "foo bar", path_allowed) == :crawlable
      assert Host.crawlable?(host_lower, "foo bar", path_allowed) == :crawlable
      assert Host.crawlable?(host_camel, "foo bar", path_allowed) == :crawlable

      refute Host.crawlable?(host_upper, "foo bar", path_disallowed) ==
               :crawlable

      refute Host.crawlable?(host_lower, "foo bar", path_disallowed) ==
               :crawlable

      refute Host.crawlable?(host_camel, "foo bar", path_disallowed) ==
               :crawlable
    end

    # If no group matches the user-agent, crawlers must obey the first group with a
    # user-agent line with a "*" value, if present. If no group satisfies either
    # condition, or no groups are present at all, no rules apply.
    # See REP RFC section "The user-agent line".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.2.1
    test "handles wildcard user-agent values" do
      robotstxt_empty = ""

      robotstxt_global = ~s"""
      user-agent: *
      allow: /
      user-agent: FooBot
      disallow: /
      """

      robotstxt_only_specific = ~s"""
      user-agent: FooBot
      allow: /
      user-agent: BarBot
      disallow: /
      user-agent: BazBot
      disallow: /
      """

      host_empty =
        Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt_empty))

      host_global =
        Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt_global))

      host_only_specific =
        Host.new(
          "http://foo.bar/",
          Gollum.Parser.parse(robotstxt_only_specific)
        )

      path = "/x/y"

      assert Host.crawlable?(host_empty, "FooBot", path) == :undefined
      refute Host.crawlable?(host_global, "FooBot", path) == :crawlable
      assert Host.crawlable?(host_global, "BarBot", path) == :crawlable
      assert Host.crawlable?(host_only_specific, "QuxBot", path) == :undefined
    end

    # Matching rules against URIs is case sensitive.
    # See REP RFC section "The Allow and Disallow lines".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.2.2
    test "matches rules against URIs case sensitive" do
      robotstxt_lowercase_url = ~s"""
      user-agent: FooBot
      disallow: /x/
      """

      robotstxt_uppercase_url = ~s"""
      user-agent: FooBot
      disallow: /X/
      """

      host_lowercase_url =
        Host.new(
          "http://foo.bar/",
          Gollum.Parser.parse(robotstxt_lowercase_url)
        )

      host_uppercase_url =
        Host.new(
          "http://foo.bar/",
          Gollum.Parser.parse(robotstxt_uppercase_url)
        )

      path = "/x/y"

      refute Host.crawlable?(host_lowercase_url, "FooBot", path) == :crawlable
      assert Host.crawlable?(host_uppercase_url, "FooBot", path) == :crawlable
    end

    # The most specific match found MUST be used. The most specific match is the
    # match that has the most octets. In case of multiple rules with the same
    # length, the least strict rule must be used.
    # See REP RFC section "The Allow and Disallow lines".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.2.2
    test "uses the most specific match" do
      path_specific = "/x/page.html"
      path_unspecific = "/x/"

      with robotstxt <- ~s"""
           user-agent: FooBot
           disallow: #{path_specific}
           allow: #{path_unspecific}
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        refute Host.crawlable?(host, "FooBot", path_specific) == :crawlable
      end

      with robotstxt <- ~s"""
           user-agent: FooBot
           allow: #{path_specific}
           disallow: #{path_unspecific}
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        assert Host.crawlable?(host, "FooBot", path_specific) == :crawlable
        refute Host.crawlable?(host, "FooBot", path_unspecific) == :crawlable
      end

      with robotstxt <- ~s"""
           user-agent: FooBot
           disallow: 
           allow: 
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        # In case of equivalent disallow and allow patterns for the same
        # user-agent, allow is used.
        assert Host.crawlable?(host, "FooBot", path_specific) == :undefined
      end

      with robotstxt <- ~s"""
           user-agent: FooBot
           disallow: /
           allow: /
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        # In case of equivalent disallow and allow patterns for the same
        # user-agent, allow is used.
        assert Host.crawlable?(host, "FooBot", "/") == :undefined
      end

      with path_a <- "/x",
           path_b <- "/x/",
           robotstxt <- ~s"""
           user-agent: FooBot
           disallow: #{path_a}
           allow: #{path_b}
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        refute Host.crawlable?(host, "FooBot", path_a) == :crawlable
        assert Host.crawlable?(host, "FooBot", path_b) == :crawlable
      end

      with robotstxt <- ~s"""
           user-agent: FooBot
           disallow: #{path_specific}
           allow: #{path_specific}
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        # In case of equivalent disallow and allow patterns for the same
        # user-agent, allow is used.
        assert Host.crawlable?(host, "FooBot", path_specific) == :undefined
      end

      with robotstxt <- ~s"""
           user-agent: FooBot
           allow: /page.
           disallow: /*.html
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        # Longest match wins.
        refute Host.crawlable?(host, "FooBot", "/page.html") == :crawlable
        assert Host.crawlable?(host, "FooBot", "/page") == :crawlable
      end

      with robotstxt <- ~s"""
           user-agent: FooBot
           allow: /x/page.
           disallow: /*.html
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        # Longest match wins.
        assert Host.crawlable?(host, "FooBot", "/x/page.html") == :crawlable
        refute Host.crawlable?(host, "FooBot", "/x/y.html") == :crawlable
      end

      with robotstxt <- ~s"""
           User-Agent: *
           Disallow: /x/
           User-Agent: FooBot
           Disallow: /y/
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        # Most specific group for FooBot allows implicitly /x/page.
        assert Host.crawlable?(host, "FooBot", "/x/page") == :crawlable
        refute Host.crawlable?(host, "FooBot", "/y/page") == :crawlable
      end
    end

    # Octets in the URI and robots.txt paths outside the range of the US-ASCII
    # coded character set, and those in the reserved range defined by RFC3986,
    # MUST be percent-encoded as defined by RFC3986 prior to comparison.
    # See REP RFC section "The Allow and Disallow lines".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.2.2
    #
    # NOTE: It's up to the caller to percent encode a URL before passing it to the
    # parser. Percent encoding URIs in the rules is unnecessary.
    test "handles encoding" do
      # /foo/bar?baz=http://foo.bar stays unencoded.
      # with robotstxt <- ~s"""
      #      User-agent: FooBot
      #      Disallow: /
      #      Allow: /foo/bar?qux=taz&baz=http://foo.bar?tar&par
      #      """,
      #      host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
      #   path = "/foo/bar?qux=taz&baz=http://foo.bar?tar&par"
      #   assert Host.crawlable?(host, "FooBot", path) == :crawlable
      # end

      # # 3 byte character: /foo/bar/ツ -> /foo/bar/%E3%83%84
      # with robotstxt <- ~s"""
      #      User-agent: FooBot
      #      Disallow: /
      #      Allow: /foo/bar/ツ
      #      """,
      #      host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
      #   assert Host.crawlable?(host, "FooBot", "/foo/bar/%E3%83%84") == :crawlable
      #   # The parser encodes the 3-byte character, but the URL is not %-encoded.
      #   refute Host.crawlable?(host, "FooBot", "/foo/bar/ツ") == :crawlable
      # end

      # # Percent encoded 3 byte character: /foo/bar/%E3%83%84 -> /foo/bar/%E3%83%84
      # with robotstxt <- ~s"""
      #      User-agent: FooBot
      #      Disallow: /
      #      Allow: /foo/bar/%E3%83%84
      #      """,
      #      host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
      #   assert Host.crawlable?(host, "FooBot", "/foo/bar/%E3%83%84") == :crawlable
      #   refute Host.crawlable?(host, "FooBot", "/foo/bar/ツ") == :crawlable
      # end

      # Percent encoded unreserved US-ASCII: /foo/bar/%62%61%7A -> NULL
      # This is illegal according to RFC3986 and while it may work here due to
      # simple string matching, it should not be relied on.
      with robotstxt <- ~s"""
           User-agent: FooBot
           Disallow: /
           Allow: /foo/bar/%62%61%7A
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        assert Host.crawlable?(host, "FooBot", "/foo/bar/baz") == :crawlable

        assert Host.crawlable?(host, "FooBot", "/foo/bar/%62%61%7A") ==
                 :crawlable
      end
    end

    # The REP RFC defines the following characters that have special meaning in
    # robots.txt:
    # # - inline comment.
    # $ - end of pattern.
    # * - any number of characters.
    # See REP RFC section "Special Characters".
    # https://www.rfc-editor.org/rfc/rfc9309.html#section-2.2.3
    test "handles special characters" do
      with robotstxt <- ~s"""
           User-agent: FooBot
           Disallow: /foo/bar/quz
           Allow: /foo/*/qux
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        refute Host.crawlable?(host, "FooBot", "/foo/bar/quz") == :crawlable
        assert Host.crawlable?(host, "FooBot", "/foo/quz") == :crawlable
        assert Host.crawlable?(host, "FooBot", "/foo//quz") == :crawlable
        assert Host.crawlable?(host, "FooBot", "/foo/bax/quz") == :crawlable
      end

      with robotstxt <- ~s"""
           User-agent: FooBot
           Disallow: /foo/bar$
           Allow: /foo/bar/qux
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        refute Host.crawlable?(host, "FooBot", "/foo/bar") == :crawlable
        assert Host.crawlable?(host, "FooBot", "/foo/bar/quz") == :crawlable
        assert Host.crawlable?(host, "FooBot", "/foo/bar/") == :crawlable
        assert Host.crawlable?(host, "FooBot", "/foo/bar/baz") == :crawlable
      end

      with robotstxt <- ~s"""
           User-agent: FooBot
           # Disallow: /
           Disallow: /foo/quz#qux
           Allow: /
           """,
           host <- Host.new("http://foo.bar/", Gollum.Parser.parse(robotstxt)) do
        assert Host.crawlable?(host, "FooBot", "/foo/bar") == :crawlable
        refute Host.crawlable?(host, "FooBot", "/foo/quz") == :crawlable
      end
    end
  end
end
