<?php

namespace Metadrop\scripthor;

use Composer\Command\BaseCommand;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

/**
 * The "scripthor:assistant" command class.
 *
 * Manually run the scaffold operation that normally happens after
 * 'composer install'.
 *
 * @internal
 */
class ComposerAssistantCommand extends BaseCommand {

  /**
   * {@inheritdoc}
   */
  protected function configure() {
    $this
      ->setName('scripthor:assistant')
      ->setAliases(['scripthor-assistant'])
      ->setDescription('Run the same assistant as after create-project.');
  }

  /**
   * {@inheritdoc}
   */
  protected function execute(InputInterface $input, OutputInterface $output) {
    $handler = new Handler($this->getComposer(), $this->getIO());
    $handler->createProjectAssistant();
  }

}
