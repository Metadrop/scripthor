<?php

namespace Metadrop;

use Composer\Composer;
use Composer\IO\IOInterface;
use Composer\Plugin\CommandEvent;

/**
 * Core class of the plugin.
 *
 * Contains the primary logic which determines the files to be fetched and
 * processed.
 *
 * @internal
 */
class Handler {

  const DIR = './scripts';
  const ENV_FILE = './.env';

  const TARGET_DIR = '../vendor/metadrop/scripthor/bin/';

  const SIMLINK_FILES = [
    'frontend-build.sh',
    'copy-content-config-entity-to-module.sh',
    'reload-local.sh',
  ];

  /**
   * The Composer service.
   *
   * @var \Composer\Composer
   */
  protected $composer;

  /**
   * Composer's I/O service.
   *
   * @var \Composer\IO\IOInterface
   */
  protected $io;

  /**
   * Handler constructor.
   *
   * @param \Composer\Composer $composer
   *   The Composer service.
   * @param \Composer\IO\IOInterface $io
   *   The Composer I/O service.
   */
  public function __construct(Composer $composer, IOInterface $io) {
    $this->composer = $composer;
    $this->io = $io;
  }

  /**
   * Create simlinks.
   *
   * @throws \Exception
   *   Error when not created
   */
  public function createSymlinks() {
    $this->io->write('Scripthor start.');

    if ($this->createScriptDir()) {
      $this->createScriptLink();
    }
    else {
      $this->io->writeError('./scripts directory not created.');
      throw new \Exception('./scripts directory not created.');
    }
    $this->io->write('Scripthor finished.');
  }

  /**
   * Create script directory.
   *
   * @return bool
   *   Exist or not directory
   */
  protected function createScriptDir() {
    if (!is_dir(self::DIR)) {
      $this->io->write('./scripts directory created with 755 permissions.');
      mkdir(self::DIR, 0755);
    }

    if (is_dir(self::DIR)) {
      return TRUE;
    }
    return FALSE;
  }

  /**
   * Create script symbolic links.
   */
  protected function createScriptLink() {

    foreach (self::SIMLINK_FILES as $file) {
      $script = self::DIR . '/' . $file;
      if (!file_exists($script)) {
        symlink(self::TARGET_DIR . $file, $script);
        $this->io->write('Script created: ' . $file);
      }
      else {
        $this->io->write('Script exists: ' . $file);
      }
    }
  }

  /**
   * Assistant on create project.
   */
  public function createProjectAssistant() {
    $project_name = $this->setUpEnvFile();
    $theme_name = str_replace('-', '_', $project_name);
    $this->setUpGit();
    $this->startDocker($theme_name);
    $this->initGrumPhp();
    $this->installDrupal($project_name);
    $this->createDirectories();
    $this->createSubTheme($theme_name);
    $this->assistantSuccess($project_name);
  }

  /**
  * Create needed directories.
  */
  protected function createDirectories() {
    $behat_dir = './web/sites/default/files/behat';
    if (!is_dir($behat_dir)) {
      mkdir($behat_dir);
    }
    $behat_dir_errors = $behat_dir . '/errors';
    if (!is_dir($behat_dir_errors)) {
      mkdir($behat_dir_errors);
    }
  }

  /**
   * Helper method to setup env file.
   */
  protected function setUpEnvFile() {
    $current_dir = basename(getcwd());
    $project_name = $this->io->ask('Please enter the project name (default to ' . $current_dir . '): ', $current_dir);
    $this->io->write('Setting up .env file');
    $env = file_get_contents(self::ENV_FILE . '.example');
    $env = str_replace('example', $project_name, $env);

    $theme_name = str_replace('-', '_', $project_name);
    $env = str_replace('THEME_PATH=/var/www/html/web/themes/custom/' . $project_name, 'THEME_PATH=/var/www/html/web/themes/custom/' . $theme_name, $env);
    file_put_contents(self::ENV_FILE, $env);

    copy('./docker-compose.override.yml.dist', './docker-compose.override.yml');

    return $project_name;
  }

  /**
   * Setup git.
   */
  protected function setUpGit() {
    if ($this->io->askConfirmation('Do you want to initialize a git repository for your new project? (Y/n) ')) {
      system('git init');
      system('git checkout -b dev');
    }
  }

  /**
   * Start docker.
   */
  protected function startDocker($theme_name) {
    system('docker-compose up -d php');
    $theme_path = '/var/www/html/web/themes/custom/' . $theme_name;
    system('docker-compose exec php mkdir -p ' . $theme_path);
    system('docker-compose up -d');
  }

  /**
   * Enable grumphp.
   */
  protected function initGrumPhp() {
    system('docker-compose exec php ./vendor/bin/grumphp git:init');
  }

  /**
   * Install Drupal with the standard profile.
   */
  protected function installDrupal($project_name) {
    if ($this->io->askConfirmation('Do you want to install Drupal? (Y/n) ')) {
      copy('./web/sites/default/example.settings.local.php', './web/sites/default/settings.local.php');
      $drush_yml = file_get_contents('./web/sites/default/example.local.drush.yml');
      $drush_yml = str_replace('example', $project_name, $drush_yml);
      file_put_contents('./web/sites/default/local.drush.yml', $drush_yml);
      system('docker-compose exec php drush si -y');
    }
  }

  /**
   * Create new sub-theme.
   */
  protected function createSubTheme(string $theme_name) {
    if ($this->io->askConfirmation('Do you want to create a Radix sub-theme? (Y/n) ')) {
      system('docker-compose exec php drush en components');
      system('docker-compose exec php drush theme:enable radix -y');
      system('docker-compose exec php drush --include="web/themes/contrib/radix" radix:create ' . $theme_name);
      system('docker-compose exec php drush theme:enable ' . $theme_name . ' -y');
      system('docker-compose exec php drush config-set system.theme default ' . $theme_name . ' -y');
      system('make frontend dev');
    }
  }

  /**
   * Assistant success message.
   */
  protected function assistantSuccess($project_name) {
    system('git add .');
    system('git commit -m "Initial commit" -n');
    $this->io->write("\n\n" . '***********************'
      . "\n" . '    CONGRATULATIONS!'
      . "\n". '***********************'
      . "\n" . 'Your new project is up and running on the following url: http://' . $project_name . '.docker.localhost:8000');
    $this->io->write('Click on the following link to start building your site:');
    system('docker-compose exec php drush uli');
  }

}
