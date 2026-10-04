import assert from "node:assert/strict";
import { test } from "node:test";
import { handle } from "./index.js";

const config = {
  redirect_status: 302,
  hosts: {
    "go.example.com": {
      index: "https://github.com/example",
      roots: {
        foo: {
          vcs: "git",
          repository: "https://github.com/example/foo",
          redirect: "https://github.com/example/foo",
          source: null,
        },
        "tools/bar": {
          vcs: "git",
          repository: "https://git.example.com/bar",
          redirect: null,
          source: {
            home: "https://git.example.com/bar",
            directory: "https://git.example.com/bar/tree/main{/dir}",
            file: "https://git.example.com/bar/blob/main{/dir}/{file}#L{line}",
          },
        },
        "tools/bar/baz": {
          vcs: "hg",
          repository: "https://hg.example.com/baz",
          redirect: "https://hg.example.com/baz",
          source: null,
        },
      },
    },
    "example.org": {
      index: null,
      roots: {
        "": {
          vcs: "mod",
          repository: "https://proxy.example.org",
          redirect: null,
          source: null,
        },
      },
    },
  },
};

const get = (url, cfg = config) => handle(new Request(url), cfg);

async function metaTags(response) {
  const html = await response.text();
  return Object.fromEntries(
    [...html.matchAll(/<meta name="([^"]+)" content="([^"]*)">/g)].map((m) => [m[1], m[2]]),
  );
}

test("go get of an import root returns its go-import tag", async () => {
  const res = await get("https://go.example.com/foo?go-get=1");
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "text/html; charset=utf-8");
  assert.deepEqual(await metaTags(res), {
    "go-import": "go.example.com/foo git https://github.com/example/foo",
  });
});

test("packages below a root resolve to that root", async () => {
  for (const path of ["/foo/", "/foo/internal/x", "//foo//bar"]) {
    const res = await get(`https://go.example.com${path}?go-get=1`);
    assert.equal(res.status, 200, path);
    assert.equal(
      (await metaTags(res))["go-import"],
      "go.example.com/foo git https://github.com/example/foo",
      path,
    );
  }
});

test("the longest matching root wins", async () => {
  let tags = await metaTags(await get("https://go.example.com/tools/bar/baz/qux?go-get=1"));
  assert.equal(tags["go-import"], "go.example.com/tools/bar/baz hg https://hg.example.com/baz");

  tags = await metaTags(await get("https://go.example.com/tools/bar/qux?go-get=1"));
  assert.equal(tags["go-import"], "go.example.com/tools/bar git https://git.example.com/bar");
});

test("roots match whole path segments only", async () => {
  assert.equal((await get("https://go.example.com/foobar?go-get=1")).status, 404);
  assert.equal((await get("https://go.example.com/tools?go-get=1")).status, 404);
});

test("go-source is included when configured", async () => {
  const tags = await metaTags(await get("https://go.example.com/tools/bar?go-get=1"));
  assert.equal(
    tags["go-source"],
    "go.example.com/tools/bar https://git.example.com/bar" +
      " https://git.example.com/bar/tree/main{/dir}" +
      " https://git.example.com/bar/blob/main{/dir}/{file}#L{line}",
  );
});

test("a root of \"\" makes the host itself an import root", async () => {
  for (const path of ["/", "/sub/pkg"]) {
    const tags = await metaTags(await get(`https://example.org${path}?go-get=1`));
    assert.equal(tags["go-import"], "example.org mod https://proxy.example.org", path);
  }
});

test("browsers are redirected to the root's redirect", async () => {
  const res = await get("https://go.example.com/foo/internal/x");
  assert.equal(res.status, 302);
  assert.equal(res.headers.get("location"), "https://github.com/example/foo");
});

test("browsers are sent to pkg.go.dev when the root has no redirect", async () => {
  let res = await get("https://go.example.com/tools/bar/sub/");
  assert.equal(res.status, 302);
  assert.equal(res.headers.get("location"), "https://pkg.go.dev/go.example.com/tools/bar/sub");

  res = await get("https://example.org/");
  assert.equal(res.headers.get("location"), "https://pkg.go.dev/example.org");
});

test("the host index redirects browsers but not the go command", async () => {
  const res = await get("https://go.example.com/");
  assert.equal(res.status, 302);
  assert.equal(res.headers.get("location"), "https://github.com/example");

  assert.equal((await get("https://go.example.com/?go-get=1")).status, 404);
});

test("unknown hosts and paths are not found", async () => {
  for (const url of [
    "https://other.example.com/foo?go-get=1",
    "https://other.example.com/",
    "https://go.example.com/nope",
    "https://go.example.com/nope?go-get=1",
    "https://go.example.com/constructor?go-get=1",
    "https://go.example.com/__proto__",
  ]) {
    assert.equal((await get(url)).status, 404, url);
  }
});

test("the configured redirect status is used", async () => {
  const res = await get("https://go.example.com/foo", { ...config, redirect_status: 301 });
  assert.equal(res.status, 301);
});

test("meta tag content is HTML-escaped", async () => {
  const cfg = {
    redirect_status: 302,
    hosts: {
      "go.example.com": {
        index: null,
        roots: {
          q: { vcs: "git", repository: 'https://x.example/"q"&<r>', redirect: null, source: null },
        },
      },
    },
  };
  const html = await (await get("https://go.example.com/q?go-get=1", cfg)).text();
  assert.match(html, /content="go\.example\.com\/q git https:\/\/x\.example\/&#34;q&#34;&#38;&#60;r&#62;"/);
});
