/**
 *
 * ApplyLearner.x10
 *
 * Rudra Distributed Learning Platform
 *
 * Copyright (c) IBM Corporation 2016
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * 3. Neither the name of Rudra nor the names of its contributors may be used
 *   to endorse or promote products derived from this software without specific
 *   prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY,OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

package rudra;

import rudra.util.Logger;
import rudra.util.Timer;
import rudra.util.SwapBuffer;
import rudra.util.MergingMonitor;

import x10.util.concurrent.AtomicBoolean;
import x10.util.Team;
import x10.io.Unserializable;
import x10.compiler.Pinned;

@Pinned public class ApplyLearner extends Learner implements Unserializable {
    val mm:MergingMonitor;
    public def this(confName:String, mbPerEpoch:UInt, spread:UInt, 
                    done:AtomicBoolean, mm: MergingMonitor,
                    team:Team, logger:Logger, lt:Int, nLearner:NativeLearner) {
        super(confName, mbPerEpoch, spread, done, nLearner, team, logger, lt);
        this.mm=mm;
    }

    val trainTimer = new Timer("Training Time:");
    val weightTimer = new Timer("Weight update Time:");
    def run(fromLearner:SwapBuffer[TimedGradient], reconciler:ApplyReconciler) {
        logger.info(()=>"Learner: started. mbPerEpoch=" + mbPerEpoch);
        var compG:TimedGradient = new TimedGradient(size); 
        compG.timeStamp = UInt.MAX_VALUE;
        val testManager = here.id==0? this.new TestManager() : null;
        if (testManager != null) testManager.initialize();
        val currentWeight = new TimedWeight(networkSize);
        initWeights();
        epochStartTime = System.nanoTime();
        while (! done.get()) {
            trainTimer.tic();
            computeGradient(compG);
            trainTimer.toc();
            val tmp=deliverGradient(compG, fromLearner);
            if (tmp != compG) {
                logger.info(()=>"Learner: Signalling data ready.");
                mm.signalData();
                compG=tmp;
                assert compG.loadSize()==0un : "ApplyLearner: the TG received from fromLearner should have zero size.";
            }
            val start = System.nanoTime();
            reconciler.fillInWeights(currentWeight); // may block
            if (currentWeight.timeStamp > timeStamp) {
                val includeMB = currentWeight.loadSize();
                timeStamp = currentWeight.timeStamp;
                totalMBProcessed += includeMB;
                deserializeWeights(currentWeight.weight);
                weightTimer.addDuration(System.nanoTime()-start);
                logger.info(()=>"Learner: accepted weights " + currentWeight);
            }
            if (testManager != null) testManager.touch();
        } // while !done

        if (testManager != null) testManager.finalize();
        logger.info(()=>"Learner: Exited main loop.");
        logger.notify(()=> "" + trainTimer);
        logger.notify(()=> "" + weightTimer);
    } //learner

}
// vim: shiftwidth=4:tabstop=4:expandtab
