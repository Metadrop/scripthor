<?php

namespace Metadrop;

use Exception;

/**
 * Class CreateSymlinks
 *
 * @package Metadrop
 */
class CreateSymlinks {

  const DIR = './scripts';

  const SIMLINK_FILES = [
    'frontend-build.sh',
    'copy-content-config-entity-to-module.sh',
    'reload-local.sh',
  ];

  /**
   * Create simlinks.
   *
   * @throws \Exception
   *   Error when not created
   */
  public static function createSymlinks() {
    $target = '../vendor/keopx/scripthor/bin/';
    $link = self::DIR . '/';

    if (!static::createScriptDir()) {
      throw new Exception('Directory not created');
    }
    else {
      foreach (self::SIMLINK_FILES as $file) {
        symlink($target . $file, $link . $file);
      }
    }
  }

  /**
   * Create script directory.
   *
   * @return bool
   *   Exist or not directory
   */
  public static function createScriptDir() {
    if (!is_dir(self::DIR)) {
      mkdir(self::DIR, 0755);
    }

    if (is_dir(self::DIR)) {
      return TRUE;
    }
    return FALSE;
  }
}
