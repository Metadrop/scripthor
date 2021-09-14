# Metadrop Composer Scripthor

## Scripthor toolset

This is a swiss knife of scripts for speed up the development on drupal projects.

Works with drupal 8+ projects.

## Usage

Drupal Composer Scripthor is used by requiring `composer require metadrop/scripthor`
in your project.

Typically, the scaffold operations run automatically as needed, e.g. after
`composer install`, so it is usually not necessary to do anything different
to scaffold a project once the configuration is set up in the project
composer.json file, as described below. To scripthor files directly, run:

### Scripthor create symlinks

```
composer scripthor:create-symlinks
```


## Scripts

### backup.sh

Simple script to backup a Drupal site. It dumps the database using drush and
tars anything under the `web` folder (this means it assumes the Drupal root is
under the `web` folder).

Destination folder can be set using the first parameter. If nothing passed, the
backups are placed under the `backups` folder.


```
$ scripts/backup.sh

Dumping database to ./backups/backups-automated/db/site-db-20210914-185115.sql-gz...OK!
Backuping codebase and files...OK!
Cleaning old backups...OK!

```

IMPORTANT! The script tries to backupo the default site. This means is not
compatible with multisite setups. You can easily create your own
script based on this for mulsites.






