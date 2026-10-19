// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image Studio: every image the app makes starts here. One desk (Create,
// Edit, Expression pack) plus the Batch tab for many characters at once,
// the same studio the desktop opens from Home and from a chat.

import { useState } from 'react';
import { ImageGen } from '../components/models/ImageGen';
import { ImageBatchesPage } from './ImageBatchesPage';
import './imageBatches.css';

export function ImageStudioPage() {
  const [error, setError] = useState('');
  return (
    <div className="page image-studio-page">
      <h2>Image Studio</h2>
      {error && <p className="error">{error}</p>}
      <ImageGen onError={setError} batch={<ImageBatchesPage embedded />} />
    </div>
  );
}
