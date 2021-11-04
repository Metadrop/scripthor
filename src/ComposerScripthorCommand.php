<?php

namespace Metadrop\scripthor;

use Composer\Command\BaseCommand;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

/**
 * The "scripthor:create-symlinks" command class.
 *
 * Manually run the scaffold operation that normally happens after
 * 'composer install'.
 *
 * @internal
 */
class ComposerScripthorCommand extends BaseCommand {

  /**
   * {@inheritdoc}
   */
  protected function configure() {
    $this
      ->setName('scripthor:create-symlinks')
      ->setAliases(['scripthor-symlinks'])
      ->setDescription('Update the Drupal scripthor files.')
      ->setHelp(
        <<<EOT
The <info>scripthor:create-symlinks</info> command places the scaffold files in their
respective locations according to the Metadrop specifications.

<info>php composer.phar scripthor:create-symlinks</info>

It is usually not necessary to call <info>scripthor:create-symlinks</info> manually,
because it is called automatically as needed, e.g. after an <info>install</info>
or <info>update</info> command. Note, though, that only packages explicitly
allowed to scaffold in the top-level composer.json will be processed by this
command.
EOT
      );
  }

  /**
   * {@inheritdoc}
   */
  protected function execute(InputInterface $input, OutputInterface $output) {
    $handler = new Handler($this->getComposer(), $this->getIO());
    $handler->createSymlinks();
  }

}
