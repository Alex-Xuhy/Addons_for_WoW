import json, re, sys, html

with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)

print("TITLE:", d.get("title"))
print("VIEWS:", d.get("views"), "| POSTS:", d.get("posts_count"), "| CREATED:", d.get("created_at"))
print()

posts = d.get("post_stream", {}).get("posts", [])
for p in posts:
    c = p.get("cooked", "")
    c = re.sub(r'<br\s*/?>', '\n', c)
    c = re.sub(r'</p>', '\n\n', c)
    c = re.sub(r'</li>', '\n', c)
    c = re.sub(r'<[^>]+>', '', c)
    c = html.unescape(c)
    c = re.sub(r'\n{3,}', '\n\n', c)
    print("=" * 72)
    print("#%s  %s  (%s)  trust=%s" % (p.get('post_number'), p.get('username'), p.get('created_at'), p.get('trust_level')))
    print("-" * 72)
    print(c.strip())
    print()
