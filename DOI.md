# Getting a DOI for EasyAnalysis

A DOI makes the citation permanent: it resolves forever even if the repository moves or the
domain lapses, and journals increasingly expect one for software.

**Everything that can be prepared in advance is done.** `.zenodo.json` is in place, so Zenodo will
use the right title, description, licence and author name instead of guessing from the GitHub
account. What remains needs a **Zenodo login**, which is why it cannot be scripted from here.

---

## The two steps (about five minutes)

### 1. Connect Zenodo to the repository — once

1. Go to **<https://zenodo.org>** and sign in with GitHub (top right → *Log in* → *GitHub*).
2. Authorise Zenodo when GitHub asks.
3. Open **<https://zenodo.org/account/settings/github/>**.
4. Find **Casanda00/easyanalysis** in the list and switch the toggle **On**.

If the repository is not listed, press *Sync now*. Zenodo only sees **public** repositories.

### 2. Publish a GitHub release — this is what mints the DOI

Zenodo archives a repository when GitHub publishes a **release**. Pushing a commit or a bare tag
is not enough — it has to be a release.

```sh
# tag the current state (match APP_VERSION in global.R)
git tag -a v0.10.16 -m "EasyAnalysis v0.10.16"
git push origin v0.10.16

# then publish the release
gh release create v0.10.16 --title "EasyAnalysis v0.10.16" --notes-from-tag
```

Or on the web: **Releases → Draft a new release →** choose the tag **→ Publish release**.

Within a few minutes Zenodo will have archived it and issued **two** DOIs.

---

## Which DOI to use

Zenodo issues two, and the difference matters:

| DOI | What it points at | Use it for |
|---|---|---|
| **Concept DOI** | the project, *all versions* | **the citation** — it always resolves to the newest release |
| **Version DOI** | one specific release | reproducibility, when a paper must name the exact version used |

**Cite the Concept DOI.** Zenodo shows it as *"Cite all versions? You can cite all versions by
using the DOI …"*.

---

## After the DOI exists — three files to update

1. **`CITATION.cff`** — uncomment the `identifiers` block and fill in the concept DOI:

   ```yaml
   identifiers:
     - type: doi
       value: 10.5281/zenodo.XXXXXXX
       description: Concept DOI for all versions
   ```

2. **`README.md`** and **`landing/documentation.html`** — add the DOI to the citation, which
   becomes:

   > Gibson, T. C. (2026). *EasyAnalysis: point-and-click statistical, machine-learning and
   > spatial analysis* (Version 0.10.16) [Computer software]. https://doi.org/10.5281/zenodo.XXXXXXX

3. **`landing/llms.txt`** — same line, so assistants quote the DOI form.

A DOI badge is also worth adding to the README:

```markdown
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)
```

---

## Notes

- **The repository must be public** at the moment the release is published, or Zenodo cannot
  archive it.
- **Zenodo archives what the tag points at**, so tag a state you are happy to have preserved
  permanently — a DOI cannot be un-issued.
- **Later releases reuse the same concept DOI** and add a new version DOI each time, so the
  citation in the docs does not need changing again.
- `.zenodo.json` has an empty `affiliation`. Fill it in if you want an institution shown on the
  record — it was left blank rather than guessed.
