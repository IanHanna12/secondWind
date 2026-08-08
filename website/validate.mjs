#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, join, normalize, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const websiteRoot = dirname(fileURLToPath(import.meta.url));
const publicBaseURL = "https://ianhanna12.github.io/secondWind/";
const failures = [];

function fail(message) {
  failures.push(message);
}

function filesBelow(directory) {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name);
    return statSync(path).isDirectory() ? filesBelow(path) : [path];
  });
}

function pageURL(htmlPath) {
  const directory = relative(websiteRoot, dirname(htmlPath));
  return directory ? `${publicBaseURL}${directory.split(sep).join("/")}/` : publicBaseURL;
}

function attributeValues(html, attribute) {
  return [...html.matchAll(new RegExp(`${attribute}="([^"]+)"`, "g"))].map((match) => match[1]);
}

function resolveInternalReference(htmlPath, reference) {
  const withoutFragment = reference.split("#", 1)[0].split("?", 1)[0];
  if (!withoutFragment) return htmlPath;

  const path = withoutFragment.startsWith("/secondWind/")
    ? join(websiteRoot, withoutFragment.slice("/secondWind/".length))
    : resolve(dirname(htmlPath), withoutFragment);

  return withoutFragment.endsWith("/") ? join(path, "index.html") : path;
}

const requiredFiles = [
  "index.html",
  "css/styles.css",
  "js/main.js",
  "robots.txt",
  "sitemap.xml",
  "assets/social-card.png",
];

for (const path of requiredFiles) {
  if (!existsSync(join(websiteRoot, path))) fail(`Missing required file: ${path}`);
}

const socialCard = readFileSync(join(websiteRoot, "assets/social-card.png"));
if (socialCard.toString("ascii", 1, 4) !== "PNG") {
  fail("assets/social-card.png is not a PNG image");
} else {
  const width = socialCard.readUInt32BE(16);
  const height = socialCard.readUInt32BE(20);
  if (width !== 1200 || height !== 630) {
    fail(`Social card must be 1200x630, found ${width}x${height}`);
  }
}

const sitemap = readFileSync(join(websiteRoot, "sitemap.xml"), "utf8");
const htmlFiles = filesBelow(websiteRoot).filter(
  (path) => extname(path) === ".html" && !path.endsWith("social-card-source.html"),
);

for (const htmlPath of htmlFiles) {
  const html = readFileSync(htmlPath, "utf8");
  const label = relative(websiteRoot, htmlPath);
  const canonical = pageURL(htmlPath);

  const requiredMetadata = [
    '<meta name="description"',
    '<meta property="og:title"',
    '<meta property="og:description"',
    '<meta property="og:url"',
    '<meta property="og:image"',
    '<meta name="twitter:card"',
    '<link rel="canonical"',
  ];

  for (const marker of requiredMetadata) {
    if (!html.includes(marker)) fail(`${label} is missing ${marker}`);
  }

  if (!html.includes(`href="${canonical}"`)) {
    fail(`${label} canonical URL does not match ${canonical}`);
  }
  if (!sitemap.includes(`<loc>${canonical}</loc>`)) {
    fail(`${label} is missing from sitemap.xml`);
  }

  const ids = attributeValues(html, "id");
  const duplicateIDs = ids.filter((id, index) => ids.indexOf(id) !== index);
  for (const id of new Set(duplicateIDs)) fail(`${label} contains duplicate id="${id}"`);

  for (const script of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try {
      JSON.parse(script[1]);
    } catch (error) {
      fail(`${label} contains invalid JSON-LD: ${error.message}`);
    }
  }

  const references = [...attributeValues(html, "href"), ...attributeValues(html, "src")];
  for (const reference of references) {
    if (/^(https?:|mailto:|data:)/.test(reference)) continue;

    const target = resolveInternalReference(htmlPath, reference);
    if (!existsSync(target)) {
      fail(`${label} references missing ${normalize(relative(websiteRoot, target))}`);
      continue;
    }

    const fragment = reference.includes("#") ? reference.split("#").at(-1) : "";
    if (fragment && extname(target) === ".html") {
      const targetHTML = readFileSync(target, "utf8");
      if (!targetHTML.includes(`id="${fragment}"`)) {
        fail(`${label} links to missing #${fragment} in ${relative(websiteRoot, target)}`);
      }
    }
  }
}

const homepage = readFileSync(join(websiteRoot, "index.html"), "utf8");
const expectedArchive = "https://github.com/IanHanna12/secondWind/releases/download/v1.0.0/Second-Wind-1.0.0.zip";
const expectedChecksums = "https://github.com/IanHanna12/secondWind/releases/download/v1.0.0/SHA256SUMS";
if (!homepage.includes(expectedArchive)) fail("Homepage is missing the direct v1.0.0 archive URL");
if (!homepage.includes(expectedChecksums)) fail("Homepage is missing the direct v1.0.0 checksum URL");

if (failures.length > 0) {
  console.error(`Website validation failed with ${failures.length} issue(s):`);
  failures.forEach((failure) => console.error(`- ${failure}`));
  process.exit(1);
}

console.log(`Website validation passed for ${htmlFiles.length} public HTML pages.`);
